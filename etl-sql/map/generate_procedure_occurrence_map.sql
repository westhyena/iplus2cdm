SET NOCOUNT ON;

-- 소스키 매핑(procedure_occurrence_map) 신규 추가
;WITH hira_proc_rows AS (
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(m.LOCAL_CD1 AS varchar(200))))) AS code_norm,
    TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) AS target_concept_id,
    TRY_CONVERT(int, m.SOURCE_CONCEPT_ID)   AS source_concept_id
  FROM [$(StagingSchema)].hira_map m
  WHERE m.TARGET_DOMAIN_ID = 'Procedure'
    AND m.INVALID_REASON IS NULL
    AND TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) IS NOT NULL
), proc_code_meta_src AS (
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(200))))) AS code_norm
  FROM [$(SrcSchema)].[PICMECHM] p
  WHERE (
    TRY_CONVERT(int, p.[보험분류]) IN (26,27)
    OR TRY_CONVERT(int, p.[수익분류]) IN (9,10)
  )
  AND TRY_CONVERT(int, p.[수가분류]) <> 3
), src_keys AS (
  SELECT 
    o.PTNTIDNO AS ptntidno,
    REPLACE(o.[진료일자], '-', '') AS [date],
    'OP' AS [source],
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),'')) AS serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),'')) AS order_no,
    UPPER(LTRIM(RTRIM(CAST(o.[청구코드] AS varchar(200))))) AS claim_code_norm
  FROM  [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, o.[진료일자]) IS NOT NULL
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),'')) IS NOT NULL
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),'')) IS NOT NULL
    AND (
      EXISTS (SELECT 1 FROM hira_proc_rows hm WHERE hm.code_norm = UPPER(LTRIM(RTRIM(CAST(o.[청구코드] AS varchar(200))))))
      OR EXISTS (SELECT 1 FROM proc_code_meta_src pm WHERE pm.code_norm = UPPER(LTRIM(RTRIM(CAST(o.[청구코드] AS varchar(200))))))
    )
  UNION
  SELECT
    i.PTNTIDNO,
    REPLACE(i.[진료일자], '-', '') AS [date],
    'IP' AS [source],
    0 AS serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),'')) AS order_no,
    UPPER(LTRIM(RTRIM(CAST(i.[청구코드] AS varchar(200))))) AS claim_code_norm
  FROM  [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, i.[진료일자]) IS NOT NULL
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),'')) IS NOT NULL
    AND (
      EXISTS (SELECT 1 FROM hira_proc_rows hm WHERE hm.code_norm = UPPER(LTRIM(RTRIM(CAST(i.[청구코드] AS varchar(200))))))
      OR EXISTS (SELECT 1 FROM proc_code_meta_src pm WHERE pm.code_norm = UPPER(LTRIM(RTRIM(CAST(i.[청구코드] AS varchar(200))))))
    )
), src_mapped AS (
  SELECT 
    s.ptntidno, s.[date], s.[source], s.serial_no, s.order_no,
    ROW_NUMBER() OVER (
      PARTITION BY s.ptntidno, s.[date], s.[source], s.serial_no, s.order_no
      ORDER BY COALESCE(hm.target_concept_id, 0), COALESCE(hm.source_concept_id, 0)
    ) AS map_index
  FROM src_keys s
  LEFT JOIN hira_proc_rows hm ON hm.code_norm = s.claim_code_norm
)
INSERT INTO  [$(StagingSchema)].procedure_occurrence_map (
    ptntidno, [date], [source], serial_no, order_no, map_index, procedure_occurrence_id)
SELECT k.ptntidno,
       k.[date],
       k.[source],
       k.serial_no,
       k.order_no,
       k.map_index,
       x.base_id + ROW_NUMBER() OVER (ORDER BY k.[date], k.order_no, k.map_index)
FROM src_mapped k
CROSS JOIN (
  SELECT ISNULL(MAX(procedure_occurrence_id),0) AS base_id
  FROM   [$(StagingSchema)].procedure_occurrence_map
) x
LEFT JOIN [$(StagingSchema)].procedure_occurrence_map m
  ON  m.ptntidno = k.ptntidno
  AND m.[date] = k.[date]
  AND m.[source] = k.[source]
  AND m.serial_no = k.serial_no
  AND m.order_no = k.order_no
  AND m.map_index = k.map_index
WHERE m.ptntidno IS NULL;
