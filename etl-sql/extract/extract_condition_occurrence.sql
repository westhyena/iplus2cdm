SET NOCOUNT ON;

-- 공통 CTE
;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), visit_map AS (
  SELECT ptntidno, [date], [source], visit_occurrence_id FROM [$(StagingSchema)].visit_occurrence_map
), hira_map AS (
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(m.LOCAL_CD1 AS varchar(200))))) AS code_norm,
    TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) AS target_concept_id,
    TRY_CONVERT(int, m.SOURCE_CONCEPT_ID)   AS source_concept_id
  FROM [$(StagingSchema)].hira_map m
  WHERE m.TARGET_DOMAIN_ID = 'Condition'
    AND m.INVALID_REASON IS NULL
    AND TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) IS NOT NULL
), all_map AS (
  SELECT code_norm, target_concept_id, source_concept_id, 1 AS priority FROM hira_map
), op_raw AS (
  SELECT
    o.PTNTIDNO,
    o.[진료일자],
    o.[상병구분],
    o.[상병코드],
    o.row_i AS row_i
  FROM  [$(SrcSchema)].[OCSDISE] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND ISNULL(o.[RO상병],'0') <> '1'
    AND ISNULL(o.[상병구분],'') <> '5'
    AND TRY_CONVERT(date, o.[진료일자]) IS NOT NULL
    AND NULLIF(LTRIM(RTRIM(o.[상병코드])),'') IS NOT NULL
), ip_raw AS (
  SELECT
    i.PTNTIDNO,
    i.[진료일자],
    i.[상병구분],
    i.[상병코드],
    i.row_i AS row_i
  FROM  [$(SrcSchema)].[OCSDISEI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND ISNULL(i.[RO상병],'0') <> '1'
    AND ISNULL(i.[상병구분],'') <> '5'
    AND TRY_CONVERT(date, i.[진료일자]) IS NOT NULL
    AND NULLIF(LTRIM(RTRIM(i.[상병코드])),'') IS NOT NULL
), op_enriched AS (
  SELECT
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.[진료일자]) AS condition_start_date,
    NULL AS condition_start_datetime,
    -- 종료일자 계산을 위해 추후 조인 필요하지만, OP는 보통 당일이 많음. 일단 NULL.
    NULL AS condition_end_datetime,
    CASE WHEN TRY_CONVERT(int, r.row_i) = 0 THEN 32902 ELSE 32908 END AS condition_status_concept_id,
    NULLIF(LTRIM(RTRIM(CAST(r.[상병코드] AS varchar(50)))), '') AS condition_source_value,
    UPPER(LTRIM(RTRIM(CAST(r.[상병코드] AS varchar(200))))) AS normalized_code,
    'OP' AS src
  FROM op_raw r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map  vm ON vm.ptntidno = r.PTNTIDNO AND vm.[date] = REPLACE(r.[진료일자], '-', '') AND vm.[source] = 'OP'
), ip_enriched AS (
  SELECT
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.[진료일자]) AS condition_start_date,
    NULL AS condition_start_datetime,
    NULL AS condition_end_datetime,
    CASE WHEN TRY_CONVERT(int, r.row_i) = 0 THEN 32902 ELSE 32908 END AS condition_status_concept_id,
    NULLIF(LTRIM(RTRIM(CAST(r.[상병코드] AS varchar(50)))), '') AS condition_source_value,
    UPPER(LTRIM(RTRIM(CAST(r.[상병코드] AS varchar(200))))) AS normalized_code,
    'IP' AS src
  FROM ip_raw r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map  vm ON vm.ptntidno = r.PTNTIDNO AND vm.[date] = REPLACE(r.[진료일자], '-', '') AND vm.[source] = 'IP'
), unioned AS (
  SELECT * FROM op_enriched
  UNION ALL
  SELECT * FROM ip_enriched
), mapped AS (
  SELECT
    u.*,
    am.target_concept_id,
    am.source_concept_id,
    ROW_NUMBER() OVER (
      PARTITION BY u.person_id, u.visit_occurrence_id, u.condition_start_date, u.normalized_code
      ORDER BY am.priority ASC
    ) AS map_rank
  FROM unioned u
  LEFT JOIN all_map am ON am.code_norm = u.normalized_code
)
SELECT
  ROW_NUMBER() OVER (ORDER BY m.person_id, m.condition_start_date) + $(MinId) AS condition_occurrence_id,
  m.person_id,
  COALESCE(m.target_concept_id, 0) AS condition_concept_id,
  m.condition_start_date,
  m.condition_start_datetime,
  COALESCE(m.condition_end_datetime, m.condition_start_date) AS condition_end_date, -- Visit End Date Lookup omitted for simplicity, defaulting to start date
  NULL AS condition_end_datetime,
  32817 AS condition_type_concept_id,
  m.condition_status_concept_id,
  NULL AS stop_reason,
  NULL AS provider_id,
  m.visit_occurrence_id,
  NULL AS visit_detail_id,
  m.condition_source_value,
  m.source_concept_id AS condition_source_concept_id,
  NULL AS condition_status_source_value
FROM mapped m
WHERE m.map_rank = 1;
