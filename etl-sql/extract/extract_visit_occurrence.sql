SET NOCOUNT ON;

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
    -- 당일 OP에 응급(E)이 하나라도 있으면 9203(ER), 아니면 9201(Outpatient)
    CASE WHEN SUM(CASE WHEN r.OTPTMETP = 'E' THEN 1 ELSE 0 END) > 0 THEN 9203 ELSE 9201 END AS visit_concept_id,
    -- 당일 최소 접수일자
    TRY_CONVERT(date, MIN(r.OTPTMDDT)) AS visit_start_date, 
    -- 당일 최소 접수일시(시간 없으면 일자 대체)
    MIN(CASE 
      WHEN r.OTPTMDTM IS NOT NULL AND LEN(r.OTPTMDTM) = 4 
      THEN DATEADD(minute, CAST(RIGHT(r.OTPTMDTM, 2) AS INT), DATEADD(hour, CAST(LEFT(r.OTPTMDTM, 2) AS INT), CAST(TRY_CONVERT(date, r.OTPTMDDT) AS DATETIME)))
      ELSE TRY_CONVERT(datetime, r.OTPTMDDT)
    END) AS visit_start_datetime, 
    -- 당일 최대 접수일자
    TRY_CONVERT(date, MAX(r.OTPTMDDT)) AS visit_end_date,
    -- 당일 최대 접수일시(시간 없으면 일자 대체)
    MAX(CASE 
      WHEN r.OTPTMDTM IS NOT NULL AND LEN(r.OTPTMDTM) = 4 
      THEN DATEADD(minute, CAST(RIGHT(r.OTPTMDTM, 2) AS INT), DATEADD(hour, CAST(LEFT(r.OTPTMDTM, 2) AS INT), CAST(TRY_CONVERT(date, r.OTPTMDDT) AS DATETIME)))
      ELSE TRY_CONVERT(datetime, r.OTPTMDDT)
    END) AS visit_end_datetime,
    32817 AS visit_type_concept_id,
    NULL AS provider_id,
    NULL AS care_site_id,
    -- 모든 값을 콤마(,)로 연결하여 표시
    STRING_AGG(REPLACE(REPLACE(REPLACE(r.OTPTMETP, CHAR(13), ''), CHAR(10), ''), CHAR(0), ''), ',') WITHIN GROUP (ORDER BY r.OTPTMETP) AS visit_source_value,
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
  GROUP BY
    vm.visit_occurrence_id,
    pm.person_id
), ip_enriched AS (
  SELECT
    vm.visit_occurrence_id,
    pm.person_id,
    9202 AS visit_concept_id,
    MIN(TRY_CONVERT(date, r.INPTADDT)) AS visit_start_date, -- 입원일 최솟값
    MIN(CASE 
      WHEN r.INPTADTM IS NOT NULL AND LEN(r.INPTADTM) = 4 
      THEN DATEADD(minute, CAST(RIGHT(r.INPTADTM, 2) AS INT), DATEADD(hour, CAST(LEFT(r.INPTADTM, 2) AS INT), CAST(TRY_CONVERT(date, r.INPTADDT) AS DATETIME)))
      ELSE TRY_CONVERT(datetime, r.INPTADDT)
    END) AS visit_start_datetime, -- 입원일시 최솟값(시간 없으면 일자 대체)
    MAX(TRY_CONVERT(date, r.INPTDSDT)) AS visit_end_date, -- 퇴원일 최댓값
    MAX(CASE 
      WHEN r.INPTDSTM IS NOT NULL AND LEN(r.INPTDSTM) = 4 
      THEN DATEADD(minute, CAST(RIGHT(r.INPTDSTM, 2) AS INT), DATEADD(hour, CAST(LEFT(r.INPTDSTM, 2) AS INT), CAST(TRY_CONVERT(date, r.INPTDSDT) AS DATETIME)))
      ELSE TRY_CONVERT(datetime, r.INPTDSDT)
    END) AS visit_end_datetime, -- 퇴원일시 최댓값
    32817 AS visit_type_concept_id,
    NULL AS provider_id,
    NULL AS care_site_id,
    NULL AS visit_source_value,
    NULL AS visit_source_concept_id,
    MAX(v1.concept_id) AS admitted_from_concept_id, -- 여러 값 중 대표값 사용
    MAX(CAST(REPLACE(REPLACE(REPLACE(r.INPTADRT, CHAR(13), ''), CHAR(10), ''), CHAR(0), '') AS varchar(50))) AS admitted_from_source_value, -- 여러 값 중 대표값 사용
    MAX(v2.concept_id) AS discharged_to_concept_id, -- 여러 값 중 대표값 사용
    MAX(CAST(REPLACE(REPLACE(REPLACE(r.INPTDSRS, CHAR(13), ''), CHAR(10), ''), CHAR(0), '') AS varchar(50))) AS discharged_to_source_value -- 여러 값 중 대표값 사용
  FROM ip_raw r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN vocab v1 ON v1.source_vocabulary = 'ADMIT_FROM' AND v1.source_code = CAST(r.INPTADRT AS varchar(200))
  LEFT JOIN vocab v2 ON v2.source_vocabulary = 'DISCHARGE_TO' AND v2.source_code = CAST(r.INPTDSRS AS varchar(200))
  JOIN visit_map vm
  ON
    vm.ptntidno = r.PTNTIDNO
    AND vm.date = r.INPTADDT
    AND vm.source = 'IP'
  GROUP BY
    vm.visit_occurrence_id,
    pm.person_id
), all_visits AS (
  SELECT * FROM op_enriched
  UNION ALL
  SELECT * FROM ip_enriched
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
FROM all_visits v;
