SET NOCOUNT ON;

-- 공통 CTE: 소스 방문 테이블에서 Min/Max 산출
;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), src_visits AS (
  SELECT
    o.PTNTIDNO AS ptntidno,
    o.OTPTMDDT AS visit_date
  FROM  [$(SrcSchema)].[PMOOTPTH] o
  WHERE o.PTNTIDNO IS NOT NULL
  UNION ALL
  SELECT
    i.PTNTIDNO,
    i.INPTADDT
  FROM  [$(SrcSchema)].[PMIINPTH] i
  WHERE i.PTNTIDNO IS NOT NULL
), person_ranges AS (
  SELECT
    pm.person_id,
    TRY_CONVERT(date, MIN(v.visit_date)) AS first_visit_date,
    TRY_CONVERT(date, MAX(v.visit_date)) AS last_visit_date
  FROM src_visits v
  JOIN person_map pm ON pm.ptntidno = v.ptntidno
  GROUP BY pm.person_id
)
SELECT
  ROW_NUMBER() OVER (ORDER BY r.person_id) + $(MinId) AS observation_period_id,
  r.person_id,
  r.first_visit_date AS observation_period_start_date,
  r.last_visit_date  AS observation_period_end_date,
  32817 AS period_type_concept_id
FROM person_ranges r
WHERE r.first_visit_date IS NOT NULL 
  AND r.last_visit_date IS NOT NULL;
