SET NOCOUNT ON;

-- 신규 소스 ID 매핑 추가
INSERT INTO  [$(StagingSchema)].person_id_map (ptntidno, person_id)
SELECT s.PTNTIDNO,
       x.base_id + ROW_NUMBER() OVER (ORDER BY s.PTNTIDNO)
FROM (
  SELECT DISTINCT PTNTIDNO
  FROM  [$(SrcSchema)].[PMCPTNT]
  WHERE PTNTIDNO IS NOT NULL
) s
CROSS JOIN (
  SELECT ISNULL(MAX(person_id),0) AS base_id FROM [$(StagingSchema)].person_id_map
) x
LEFT JOIN [$(StagingSchema)].person_id_map m
  ON m.ptntidno = s.PTNTIDNO
WHERE m.ptntidno IS NULL;
