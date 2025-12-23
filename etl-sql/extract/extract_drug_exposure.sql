SET NOCOUNT ON;

-- default param
DECLARE @MinId INT = $(MinId); 

-- 공통 맵/소스 CTE
;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), visit_map AS (
  SELECT ptntidno, [date], [source], visit_occurrence_id FROM [$(StagingSchema)].visit_occurrence_map
), keys_map AS (
  SELECT ptntidno, [date], [source], serial_no, order_no, map_index, drug_exposure_id 
  FROM [$(StagingSchema)].drug_exposure_map
  WHERE drug_exposure_id > $(MinId)
), drug_map AS (
  -- 사용자 제공 매핑: 청구코드 정규화 후 매핑
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(m.source_code AS varchar(200))))) AS code_norm,
    TRY_CONVERT(int, m.target_concept_id) AS target_concept_id,
    TRY_CONVERT(int, m.source_concept_id) AS source_concept_id
  FROM [$(StagingSchema)].drug_vocabulary_map m
  WHERE TRY_CONVERT(int, m.target_concept_id) IS NOT NULL
), hira_map AS (
  -- HIRA 매핑: TARGET_DOMAIN_ID = 'Drug' 인 경우만 사용, 무효(INVALID_REASON) 제외
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(m.LOCAL_CD1 AS varchar(200))))) AS code_norm,
    TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) AS target_concept_id,
    TRY_CONVERT(int, m.SOURCE_CONCEPT_ID)   AS source_concept_id
  FROM [$(StagingSchema)].hira_map m
  WHERE m.TARGET_DOMAIN_ID = 'Drug'
    AND m.INVALID_REASON IS NULL
    AND TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) IS NOT NULL
), all_map AS (
  SELECT code_norm, target_concept_id, source_concept_id FROM drug_map
  UNION
  SELECT code_norm, target_concept_id, source_concept_id FROM hira_map
), op_raw AS (
  -- 외래(OCSSLIP)
  SELECT
    o.PTNTIDNO,
    o.[진료일자]           AS svc_date,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),'')) AS serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),'')) AS order_no,
    o.[청구코드]           AS claim_code,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[투여일수])),'')) AS days_supply,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(o.[투여량])),''))  AS dose_amount,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(o.[투여횟수])),'')) AS dose_frequency
  FROM  [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, o.[진료일자]) IS NOT NULL
    AND o.[수가분류] = 3
), ip_raw AS (
  -- 입원(OCSSLIPI)
  SELECT
    i.PTNTIDNO,
    i.[진료일자]           AS svc_date,
    0 AS serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),'')) AS order_no,
    i.[청구코드]           AS claim_code,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[투여일수])),'')) AS days_supply,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(i.[투여량])),''))  AS dose_amount,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(i.[투여횟수])),'')) AS dose_frequency
  FROM  [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, i.[진료일자]) IS NOT NULL
    AND i.[수가분류] = 3
), op_enriched AS (
  SELECT
    r.PTNTIDNO AS k_ptntidno,
    REPLACE(r.svc_date, '-', '') AS k_date,
    'OP' AS k_source,
    r.serial_no AS k_serial_no,
    r.order_no AS k_order_no,
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.svc_date) AS drug_exposure_start_date,
    NULL AS drug_exposure_start_datetime,
    -- 종료일자: 진료일자 + 투여일수 - 1 (일수 없으면 시작일자)
    TRY_CONVERT(date, DATEADD(day, COALESCE(r.days_supply, 1) - 1, TRY_CONVERT(date, r.svc_date))) AS drug_exposure_end_date,
    NULL AS drug_exposure_end_datetime,
    CAST(r.claim_code AS varchar(50)) AS drug_source_value,
    UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200))))) AS normalized_code,
    r.days_supply,
    r.dose_amount,
    r.dose_frequency,
    'OP' AS src
  FROM op_raw r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map  vm ON vm.ptntidno = r.PTNTIDNO AND vm.[date] = REPLACE(r.svc_date, '-', '') AND vm.[source] = 'OP'
), ip_enriched AS (
  SELECT
    r.PTNTIDNO AS k_ptntidno,
    REPLACE(r.svc_date, '-', '') AS k_date,
    'IP' AS k_source,
    r.serial_no AS k_serial_no,
    r.order_no AS k_order_no,
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.svc_date) AS drug_exposure_start_date,
    NULL AS drug_exposure_start_datetime,
    TRY_CONVERT(date, DATEADD(day, COALESCE(r.days_supply, 1) - 1, TRY_CONVERT(date, r.svc_date))) AS drug_exposure_end_date,
    NULL AS drug_exposure_end_datetime,
    CAST(r.claim_code AS varchar(50)) AS drug_source_value,
    UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200))))) AS normalized_code,
    r.days_supply,
    r.dose_amount,
    r.dose_frequency,
    'IP' AS src
  FROM ip_raw r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map  vm ON vm.ptntidno = r.PTNTIDNO AND vm.[date] = REPLACE(r.svc_date, '-', '') AND vm.[source] = 'IP'
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
      PARTITION BY u.k_ptntidno, u.k_date, u.k_source, u.k_serial_no, u.k_order_no
      ORDER BY COALESCE(am.target_concept_id, 0), COALESCE(am.source_concept_id, 0)
    ) AS map_index
  FROM unioned u
  LEFT JOIN all_map am ON am.code_norm = u.normalized_code
)
SELECT
    km.drug_exposure_id,
    m.person_id,
    COALESCE(m.target_concept_id, 0) AS drug_concept_id,
    m.drug_exposure_start_date,
    m.drug_exposure_start_datetime,
    m.drug_exposure_end_date,
    m.drug_exposure_end_datetime,
    NULL AS verbatim_end_date,
    32817 AS drug_type_concept_id,
    NULL AS stop_reason,
    NULL AS refills,
    -- quantity = 투여량 x 투여횟수
    CASE 
      WHEN m.dose_amount IS NULL OR m.dose_frequency IS NULL THEN NULL
      ELSE TRY_CONVERT(float, m.dose_amount * m.dose_frequency)
    END AS quantity,
    m.days_supply,
    NULL AS sig,
    NULL AS route_concept_id,
    NULL AS lot_number,
    NULL AS provider_id,
    m.visit_occurrence_id,
    NULL AS visit_detail_id,
    m.drug_source_value,
    m.source_concept_id AS drug_source_concept_id,
    NULL AS route_source_value,
    NULL AS dose_unit_source_value
  FROM mapped m
  LEFT JOIN keys_map km 
    ON km.ptntidno = m.k_ptntidno
    AND km.[date] = m.k_date
    AND km.[source] = m.k_source
    AND km.serial_no = m.k_serial_no
    AND km.order_no = m.k_order_no
    AND km.map_index = m.map_index;
