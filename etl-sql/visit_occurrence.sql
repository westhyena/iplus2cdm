SET NOCOUNT ON;

-- 신규 visit 소스키 매핑 추가 (외래/응급 OP, 입원 IP)
;WITH src_keys AS (
  SELECT 
    o.PTNTIDNO AS ptntidno,
    o.OTPTMDDT AS date,
    'OP' AS source
  FROM  [$(SrcSchema)].[PMOOTPTH] o
  WHERE o.PTNTIDNO IS NOT NULL
  UNION
  SELECT
    i.PTNTIDNO,
    i.INPTADDT,
    'IP'
  FROM  [$(SrcSchema)].[PMIINPTH] i
  WHERE i.PTNTIDNO IS NOT NULL
)
INSERT INTO  [$(StagingSchema)].visit_occurrence_map (
    ptntidno, date, source, visit_occurrence_id)
SELECT k.ptntidno,
       k.date,
       k.source,
       x.base_id + ROW_NUMBER() OVER (ORDER BY k.date)
FROM src_keys k
CROSS JOIN (
  SELECT ISNULL(MAX(visit_occurrence_id),0) AS base_id
  FROM   [$(StagingSchema)].visit_occurrence_map
) x
LEFT JOIN [$(StagingSchema)].visit_occurrence_map m
  ON
  m.ptntidno = k.ptntidno
  AND m.date = k.date
  AND m.source = k.source
WHERE m.ptntidno IS NULL;

-- 공통 CTE 준비
;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), visit_map AS (
  SELECT ptntidno, date, source, visit_occurrence_id FROM [$(StagingSchema)].visit_occurrence_map
), vocab AS (
  SELECT source_vocabulary, source_code, concept_id FROM [$(StagingSchema)].vocabulary_map
), op_raw AS (
  SELECT
    o.PTNTIDNO,
    o.OTPTMDDT,
    o.OTPTMDTM,
    o.OTPTMETP
  FROM  [$(SrcSchema)].[PMOOTPTH] o
  WHERE o.PTNTIDNO IS NOT NULL
), ip_raw AS (
  SELECT
    i.PTNTIDNO,
    i.INPTADDT,
    i.INPTADTM,
    i.INPTDSDT,
    i.INPTDSTM,
    i.INPTADRT,
    i.INPTDSRS
  FROM  [$(SrcSchema)].[PMIINPTH] i
  WHERE i.PTNTIDNO IS NOT NULL
), op_enriched AS (
  SELECT
    vm.visit_occurrence_id,
    pm.person_id,
    CASE
        WHEN r.OTPTMETP = 'E' THEN 9203
        ELSE 9201
    END AS visit_concept_id,
    TRY_CONVERT(date, r.OTPTMDDT) AS visit_start_date,
    COALESCE(TRY_CONVERT(datetime, r.OTPTMDTM), TRY_CONVERT(datetime, r.OTPTMDDT)) AS visit_start_datetime,
    TRY_CONVERT(date, r.OTPTMDDT) AS visit_end_date,
    COALESCE(TRY_CONVERT(datetime, r.OTPTMDTM), TRY_CONVERT(datetime, r.OTPTMDDT)) AS visit_end_datetime,
    32817 AS visit_type_concept_id,
    NULL AS provider_id,
    NULL AS care_site_id,
    r.OTPTMETP AS visit_source_value,
    NULL AS visit_source_concept_id,
    NULL AS admitted_from_concept_id,
    NULL AS admitted_from_source_value,
    NULL AS discharged_to_concept_id,
    NULL AS discharged_to_source_value
  FROM op_raw r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  JOIN visit_map vm 
  ON 
    vm.ptntidno = r.PTNTIDNO
    AND vm.date = r.OTPTMDDT
    AND vm.source = 'OP'
), ip_enriched AS (
  SELECT
    vm.visit_occurrence_id,
    pm.person_id,
    9202 AS visit_concept_id,
    TRY_CONVERT(date, r.INPTADDT) AS visit_start_date,
    COALESCE(TRY_CONVERT(datetime, r.INPTADTM), TRY_CONVERT(datetime, r.INPTADDT)) AS visit_start_datetime,
    TRY_CONVERT(date, r.INPTDSDT) AS visit_end_date,
    TRY_CONVERT(datetime, r.INPTDSTM) AS visit_end_datetime,
    32817 AS visit_type_concept_id,
    NULL AS provider_id,
    NULL AS care_site_id,
    NULL AS visit_source_value,
    NULL AS visit_source_concept_id,
    v1.concept_id AS admitted_from_concept_id,
    CAST(r.INPTADRT AS varchar(50)) AS admitted_from_source_value,
    v2.concept_id AS discharged_to_concept_id,
    CAST(r.INPTDSRS AS varchar(50)) AS discharged_to_source_value
  FROM ip_raw r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN vocab v1 ON v1.source_vocabulary = 'ADMIT_FROM' AND v1.source_code = CAST(r.INPTADRT AS varchar(200))
  LEFT JOIN vocab v2 ON v2.source_vocabulary = 'DISCHARGE_TO' AND v2.source_code = CAST(r.INPTDSRS AS varchar(200))
  JOIN visit_map vm
  ON
    vm.ptntidno = r.PTNTIDNO
    AND vm.date = r.INPTADDT
    AND vm.source = 'IP'
), all_visits AS (
  SELECT * FROM op_enriched
  UNION ALL
  SELECT * FROM ip_enriched
)

-- 신규만 삽입
INSERT INTO [$(CdmSchema)].[visit_occurrence](
  visit_occurrence_id,
  person_id,
  visit_concept_id,
  visit_start_date,
  visit_start_datetime,
  visit_end_date,
  visit_end_datetime,
  visit_type_concept_id,
  provider_id,
  care_site_id,
  visit_source_value,
  visit_source_concept_id,
  admitted_from_concept_id,
  admitted_from_source_value,
  discharged_to_concept_id,
  discharged_to_source_value,
  preceding_visit_occurrence_id
)
SELECT v.visit_occurrence_id,
       v.person_id,
       v.visit_concept_id,
       v.visit_start_date,
       v.visit_start_datetime,
       COALESCE(v.visit_end_date, v.visit_start_date) AS visit_end_date,
       v.visit_end_datetime,
       v.visit_type_concept_id,
       v.provider_id,
       v.care_site_id,
       v.visit_source_value,
       v.visit_source_concept_id,
       v.admitted_from_concept_id,
       v.admitted_from_source_value,
       v.discharged_to_concept_id,
       v.discharged_to_source_value,
       NULL AS preceding_visit_occurrence_id
FROM all_visits v
WHERE NOT EXISTS (
  SELECT 1 FROM [$(CdmSchema)].[visit_occurrence] t WHERE t.visit_occurrence_id = v.visit_occurrence_id
);


