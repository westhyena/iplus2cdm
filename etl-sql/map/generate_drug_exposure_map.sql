SET NOCOUNT ON;

-- 소스키 매핑(drug_exposure_map) 신규 추가
;WITH src_keys AS (
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
    AND o.[수가분류] = 3
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),'')) IS NOT NULL
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),'')) IS NOT NULL
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
    AND i.[수가분류] = 3
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),'')) IS NOT NULL
), drug_map AS (
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(m.source_code AS varchar(200))))) AS code_norm
  FROM [$(StagingSchema)].drug_vocabulary_map m
  WHERE TRY_CONVERT(int, m.target_concept_id) IS NOT NULL
), hira_map AS (
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(m.LOCAL_CD1 AS varchar(200))))) AS code_norm
  FROM [$(StagingSchema)].hira_map m
  WHERE m.TARGET_DOMAIN_ID = 'Drug'
    AND m.INVALID_REASON IS NULL
    AND TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) IS NOT NULL
), all_map AS (
  SELECT code_norm FROM drug_map
  UNION
  SELECT code_norm FROM hira_map
), src_mapped AS (
  SELECT 
    s.ptntidno, s.[date], s.[source], s.serial_no, s.order_no,
    ROW_NUMBER() OVER (
      PARTITION BY s.ptntidno, s.[date], s.[source], s.serial_no, s.order_no
      ORDER BY (CASE WHEN am.code_norm IS NULL THEN 1 ELSE 0 END), s.claim_code_norm
    ) AS map_index
  FROM src_keys s
  LEFT JOIN all_map am ON am.code_norm = s.claim_code_norm
)
INSERT INTO  [$(StagingSchema)].drug_exposure_map (
    ptntidno, [date], [source], serial_no, order_no, map_index, drug_exposure_id)
SELECT k.ptntidno,
       k.[date],
       k.[source],
       k.serial_no,
       k.order_no,
       k.map_index,
       x.base_id + ROW_NUMBER() OVER (ORDER BY k.[date], k.order_no, k.map_index)
FROM src_mapped k
CROSS JOIN (
  SELECT ISNULL(MAX(drug_exposure_id),0) AS base_id
  FROM   [$(StagingSchema)].drug_exposure_map
) x
LEFT JOIN [$(StagingSchema)].drug_exposure_map m
  ON  m.ptntidno = k.ptntidno
  AND m.[date] = k.[date]
  AND m.[source] = k.[source]
  AND m.serial_no = k.serial_no
  AND m.order_no = k.order_no
  AND m.map_index = k.map_index
WHERE m.ptntidno IS NULL;
