SET NOCOUNT ON;

-- default param
DECLARE @MinId INT = $(MinId); 
-- if passed as env var/sqlcmd arg, it works. If not, it might fail if variable not defined?
-- Sqlcmd requires variables to be defined. I'll assume the driver passes it.
-- Or I can do: IF '$(MinId)' = '' ... but SQLCMD parser is tricky.
-- Better: `WHERE km.procedure_occurrence_id > CONVERT(INT, '$(MinId)')` and ensure driver passes 0 if empty.

-- 공통/소스 CTE
;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), visit_map AS (
  SELECT ptntidno, [date], [source], visit_occurrence_id FROM [$(StagingSchema)].visit_occurrence_map
), keys_map AS (
  SELECT ptntidno, [date], [source], serial_no, order_no, map_index, procedure_occurrence_id 
  FROM [$(StagingSchema)].procedure_occurrence_map
  WHERE procedure_occurrence_id > $(MinId)  -- Optimization: Incremental Extract
), hira_proc_map AS (
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(m.LOCAL_CD1 AS varchar(200))))) AS code_norm,
    TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) AS target_concept_id,
    TRY_CONVERT(int, m.SOURCE_CONCEPT_ID)   AS source_concept_id
  FROM [$(StagingSchema)].hira_map m
  WHERE m.TARGET_DOMAIN_ID = 'Procedure'
    AND m.INVALID_REASON IS NULL
    AND TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) IS NOT NULL
), proc_code_meta AS (
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(200))))) AS code_norm,
    TRY_CONVERT(int, p.[보험분류]) AS 보험분류,
    TRY_CONVERT(int, p.[수익분류]) AS 수익분류
  FROM [$(SrcSchema)].[PICMECHM] p
  WHERE (
    TRY_CONVERT(int, p.[보험분류]) IN (26,27)
    OR TRY_CONVERT(int, p.[수익분류]) IN (9,10)
  )
  AND TRY_CONVERT(int, p.[수가분류]) <> 3
), op_raw AS (
  SELECT
    o.PTNTIDNO,
    o.[진료일자] AS svc_date,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),'')) AS serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),'')) AS order_no,
    o.[청구코드] AS claim_code
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, o.[진료일자]) IS NOT NULL
), ip_raw AS (
  SELECT
    i.PTNTIDNO,
    i.[진료일자] AS svc_date,
    0 AS serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),'')) AS order_no,
    i.[청구코드] AS claim_code
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, i.[진료일자]) IS NOT NULL
), op_filtered AS (
  SELECT r.*
  FROM op_raw r
  WHERE 
    EXISTS (
      SELECT 1 FROM hira_proc_map hm 
      WHERE hm.code_norm = UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200)))))
    )
    OR EXISTS (
      SELECT 1 FROM proc_code_meta pm
      WHERE pm.code_norm = UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200)))))
    )
), ip_filtered AS (
  SELECT r.*
  FROM ip_raw r
  WHERE 
    EXISTS (
      SELECT 1 FROM hira_proc_map hm 
      WHERE hm.code_norm = UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200)))))
    )
    OR EXISTS (
      SELECT 1 FROM proc_code_meta pm
      WHERE pm.code_norm = UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200)))))
    )
), op_enriched AS (
  SELECT
    r.PTNTIDNO AS k_ptntidno,
    REPLACE(r.svc_date, '-', '') AS k_date,
    'OP' AS k_source,
    r.serial_no AS k_serial_no,
    r.order_no AS k_order_no,
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.svc_date) AS procedure_date,
    NULL AS procedure_datetime,
    CAST(r.claim_code AS varchar(50)) AS procedure_source_value,
    UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200))))) AS normalized_code,
    'OP' AS src
  FROM op_filtered r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map vm ON vm.ptntidno = r.PTNTIDNO AND vm.[date] = REPLACE(r.svc_date, '-', '') AND vm.[source] = 'OP'
), ip_enriched AS (
  SELECT
    r.PTNTIDNO AS k_ptntidno,
    REPLACE(r.svc_date, '-', '') AS k_date,
    'IP' AS k_source,
    r.serial_no AS k_serial_no,
    r.order_no AS k_order_no,
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.svc_date) AS procedure_date,
    NULL AS procedure_datetime,
    CAST(r.claim_code AS varchar(50)) AS procedure_source_value,
    UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200))))) AS normalized_code,
    'IP' AS src
  FROM ip_filtered r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map vm ON vm.ptntidno = r.PTNTIDNO AND vm.[date] = REPLACE(r.svc_date, '-', '') AND vm.[source] = 'IP'
), unioned AS (
  SELECT * FROM op_enriched
  UNION ALL
  SELECT * FROM ip_enriched
), mapped AS (
  SELECT
    u.*,
    hm.target_concept_id,
    hm.source_concept_id,
    ROW_NUMBER() OVER (
      PARTITION BY u.k_ptntidno, u.k_date, u.k_source, u.k_serial_no, u.k_order_no
      ORDER BY COALESCE(hm.target_concept_id, 0), COALESCE(hm.source_concept_id, 0)
    ) AS map_index
  FROM unioned u
  LEFT JOIN hira_proc_map hm ON hm.code_norm = u.normalized_code
)
SELECT
    km.procedure_occurrence_id,
    m.person_id,
    COALESCE(m.target_concept_id, 0) AS procedure_concept_id,
    m.procedure_date,
    m.procedure_datetime,
    32817 AS procedure_type_concept_id,
    NULL AS modifier_concept_id,
    NULL AS quantity,
    NULL AS provider_id,
    m.visit_occurrence_id,
    NULL AS visit_detail_id,
    m.procedure_source_value,
    m.source_concept_id AS procedure_source_concept_id,
    NULL AS modifier_source_value
  FROM mapped m
  JOIN keys_map km 
    ON km.ptntidno = m.k_ptntidno
    AND km.[date] = m.k_date
    AND km.[source] = m.k_source
    AND km.serial_no = m.k_serial_no
    AND km.order_no = m.k_order_no
    AND km.map_index = m.map_index;
