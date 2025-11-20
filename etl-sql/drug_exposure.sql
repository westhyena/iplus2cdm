SET NOCOUNT ON;

-- drug_exposure_id 자동증가: 시퀀스와 기본값 보장
BEGIN TRY
  BEGIN TRAN;

  -- 1) 시퀀스 없으면 생성
  IF NOT EXISTS (
    SELECT 1
    FROM sys.sequences sq
    JOIN sys.schemas sc ON sc.schema_id = sq.schema_id
    WHERE sq.name = 'seq_drug_exposure_id' AND sc.name = '$(CdmSchema)'
  )
  BEGIN
    EXEC('CREATE SEQUENCE [$(CdmSchema)].[seq_drug_exposure_id] AS INT START WITH 1 INCREMENT BY 1');
  END;

  -- 2) 현재 MAX + 1로 RESTART (기존 데이터 고려)
  DECLARE @max_id INT = ISNULL((SELECT MAX(drug_exposure_id) FROM [$(CdmSchema)].[drug_exposure]), 0);
  DECLARE @restart_sql nvarchar(400) = N'ALTER SEQUENCE [$(CdmSchema)].[seq_drug_exposure_id] RESTART WITH ' + CAST(@max_id + 1 AS nvarchar(20));
  EXEC(@restart_sql);

  -- 3) 컬럼에 기본값(시퀀스) 없으면 추가
  IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.default_object_id = dc.object_id
    JOIN sys.tables t ON t.object_id = c.object_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = '$(CdmSchema)'
      AND t.name = 'drug_exposure'
      AND c.name = 'drug_exposure_id'
  )
  BEGIN
    ALTER TABLE [$(CdmSchema)].[drug_exposure]
      ADD CONSTRAINT DF_drug_exposure_id_seq
      DEFAULT (NEXT VALUE FOR [$(CdmSchema)].[seq_drug_exposure_id]) FOR drug_exposure_id;
  END;

  COMMIT;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK;
  THROW;
END CATCH

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

-- 공통 맵/소스 CTE
;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), visit_map AS (
  SELECT ptntidno, [date], [source], visit_occurrence_id FROM [$(StagingSchema)].visit_occurrence_map
), keys_map AS (
  SELECT ptntidno, [date], [source], serial_no, order_no, map_index, drug_exposure_id FROM [$(StagingSchema)].drug_exposure_map
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
), final_enriched AS (
  SELECT
    km.drug_exposure_id,
    m.person_id,
    COALESCE(m.target_concept_id, 0) AS drug_concept_id,
    m.drug_exposure_start_date,
    m.drug_exposure_start_datetime,
    m.drug_exposure_end_date,
    m.drug_exposure_end_datetime,
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
   AND km.map_index = m.map_index
)

-- 신규만 삽입
INSERT INTO [$(CdmSchema)].[drug_exposure](
  drug_exposure_id,
  person_id,
  drug_concept_id,
  drug_exposure_start_date,
  drug_exposure_start_datetime,
  drug_exposure_end_date,
  drug_exposure_end_datetime,
  verbatim_end_date,
  drug_type_concept_id,
  stop_reason,
  refills,
  quantity,
  days_supply,
  sig,
  route_concept_id,
  lot_number,
  provider_id,
  visit_occurrence_id,
  visit_detail_id,
  drug_source_value,
  drug_source_concept_id,
  route_source_value,
  dose_unit_source_value
)
SELECT v.drug_exposure_id,
       v.person_id,
       v.drug_concept_id,
       v.drug_exposure_start_date,
       v.drug_exposure_start_datetime,
       v.drug_exposure_end_date,
       v.drug_exposure_end_datetime,
       NULL AS verbatim_end_date,
       v.drug_type_concept_id,
       v.stop_reason,
       v.refills,
       v.quantity,
       v.days_supply,
       v.sig,
       v.route_concept_id,
       v.lot_number,
       v.provider_id,
       v.visit_occurrence_id,
       v.visit_detail_id,
       v.drug_source_value,
       v.drug_source_concept_id,
       v.route_source_value,
       v.dose_unit_source_value
FROM final_enriched v
WHERE NOT EXISTS (
  SELECT 1 FROM [$(CdmSchema)].[drug_exposure] t WHERE t.drug_exposure_id = v.drug_exposure_id
);



