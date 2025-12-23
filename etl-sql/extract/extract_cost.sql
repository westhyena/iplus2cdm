SET NOCOUNT ON;

-- default param
DECLARE @MinId INT = 0; -- Cost doesn't support MinId easily as it comes from multiple sources. Default 0.

-- 1. Procedure Costs
SELECT
  km.procedure_occurrence_id AS cost_event_id,
  'Procedure' AS cost_domain_id,
  32817       AS cost_type_concept_id,
  44818598    AS currency_concept_id, -- KRW
  u.amount    AS total_cost,
  NULL AS total_charge,
  NULL AS total_paid,
  NULL AS paid_by_payer,
  NULL AS paid_by_patient,
  NULL AS paid_patient_copay,
  NULL AS paid_patient_coinsurance,
  NULL AS paid_patient_deductible,
  NULL AS paid_by_primary,
  NULL AS paid_ingredient_cost,
  NULL AS paid_dispensing_fee,
  NULL AS payer_plan_period_id,
  NULL AS amount_allowed,
  NULL AS revenue_code_concept_id,
  NULL AS revenue_code_source_value,
  NULL AS drg_concept_id,
  NULL AS drg_source_value
FROM (
  SELECT
    o.PTNTIDNO            AS k_ptntidno,
    REPLACE(o.[진료일자], '-', '') AS k_date,
    'OP'                  AS k_source,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),''))   AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
  UNION ALL
  SELECT
    i.PTNTIDNO            AS k_ptntidno,
    REPLACE(i.[진료일자], '-', '') AS k_date,
    'IP'                  AS k_source,
    0                     AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
) u
JOIN [$(StagingSchema)].procedure_occurrence_map km
  ON km.ptntidno = u.k_ptntidno
 AND km.[date]   = u.k_date
 AND km.[source] = u.k_source
 AND km.serial_no = u.k_serial_no
 AND km.order_no  = u.k_order_no
 AND km.map_index = 1
WHERE u.amount IS NOT NULL AND u.amount <> 0

UNION ALL

-- 2. Drug Costs
SELECT
  km.drug_exposure_id AS cost_event_id,
  'Drug' AS cost_domain_id,
  32817  AS cost_type_concept_id,
  44818598 AS currency_concept_id,
  u.amount AS total_cost,
  NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM (
  SELECT
    o.PTNTIDNO            AS k_ptntidno,
    REPLACE(o.[진료일자], '-', '') AS k_date,
    'OP'                  AS k_source,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),''))   AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
  UNION ALL
  SELECT
    i.PTNTIDNO            AS k_ptntidno,
    REPLACE(i.[진료일자], '-', '') AS k_date,
    'IP'                  AS k_source,
    0                     AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
) u
JOIN [$(StagingSchema)].drug_exposure_map km
  ON km.ptntidno = u.k_ptntidno
 AND km.[date]   = u.k_date
 AND km.[source] = u.k_source
 AND km.serial_no = u.k_serial_no
 AND km.order_no  = u.k_order_no
 AND km.map_index = 1
WHERE u.amount IS NOT NULL AND u.amount <> 0

UNION ALL

-- 3. Device Costs
SELECT
  km.device_exposure_id AS cost_event_id,
  'Device' AS cost_domain_id,
  32817    AS cost_type_concept_id,
  44818598 AS currency_concept_id,
  u.amount AS total_cost,
  NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM (
  SELECT
    o.PTNTIDNO            AS k_ptntidno,
    REPLACE(o.[진료일자], '-', '') AS k_date,
    'OP'                  AS k_source,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),''))   AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
  UNION ALL
  SELECT
    i.PTNTIDNO            AS k_ptntidno,
    REPLACE(i.[진료일자], '-', '') AS k_date,
    'IP'                  AS k_source,
    0                     AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
) u
JOIN [$(StagingSchema)].device_exposure_map km
  ON km.ptntidno = u.k_ptntidno
 AND km.[date]   = u.k_date
 AND km.[source] = u.k_source
 AND km.serial_no = u.k_serial_no
 AND km.order_no  = u.k_order_no
 AND km.map_index = 1
WHERE u.amount IS NOT NULL AND u.amount <> 0

UNION ALL

-- 4. Observation Costs
SELECT
  km.observation_id AS cost_event_id,
  'Observation' AS cost_domain_id,
  32817         AS cost_type_concept_id,
  44818598      AS currency_concept_id,
  u.amount      AS total_cost,
  NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM (
  SELECT
    o.PTNTIDNO            AS k_ptntidno,
    REPLACE(o.[진료일자], '-', '') AS k_date,
    'OP'                  AS k_source,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),''))   AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
  UNION ALL
  SELECT
    i.PTNTIDNO            AS k_ptntidno,
    REPLACE(i.[진료일자], '-', '') AS k_date,
    'IP'                  AS k_source,
    0                     AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
) u
JOIN [$(StagingSchema)].observation_map km
  ON km.ptntidno = u.k_ptntidno
 AND km.[date]   = u.k_date
 AND km.[source] = u.k_source
 AND km.serial_no = u.k_serial_no
 AND km.order_no  = u.k_order_no
 AND km.map_index = 1
WHERE u.amount IS NOT NULL AND u.amount <> 0;
