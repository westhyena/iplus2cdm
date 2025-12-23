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
