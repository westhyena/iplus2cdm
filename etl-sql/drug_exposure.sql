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

-- 공통 맵/소스 CTE
;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), visit_map AS (
  SELECT ptntidno, [date], [source], visit_occurrence_id FROM [$(StagingSchema)].visit_occurrence_map
), drug_map AS (
  -- 사용자 제공 매핑: 청구코드 정규화 후 매핑
  SELECT
    UPPER(LTRIM(RTRIM(CAST(m.source_code AS varchar(200))))) AS code_norm,
    TRY_CONVERT(int, m.target_concept_id) AS target_concept_id,
    TRY_CONVERT(int, m.source_concept_id) AS source_concept_id
  FROM [$(StagingSchema)].drug_vocabulary_map m
  WHERE TRY_CONVERT(int, m.target_concept_id) IS NOT NULL
), hira_map AS (
  -- HIRA 매핑: SOURCE_DOMAIN_ID = 'Drug' 인 경우만 사용, 무효(INVALID_REASON) 제외
  SELECT
    UPPER(LTRIM(RTRIM(CAST(m.LOCAL_CD1 AS varchar(200))))) AS code_norm,
    TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) AS target_concept_id,
    TRY_CONVERT(int, m.SOURCE_CONCEPT_ID)   AS source_concept_id
  FROM [$(StagingSchema)].hira_map m
  WHERE m.SOURCE_DOMAIN_ID = 'Drug'
    AND m.INVALID_REASON IS NULL
    AND TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) IS NOT NULL
), op_raw AS (
  -- 외래(OCSSLIP)
  SELECT
    o.PTNTIDNO,
    o.[진료일자]           AS svc_date,
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
), final_enriched AS (
  SELECT
    u.person_id,
    COALESCE(dm.target_concept_id, hm.target_concept_id, 0) AS drug_concept_id,
    u.drug_exposure_start_date,
    u.drug_exposure_start_datetime,
    u.drug_exposure_end_date,
    u.drug_exposure_end_datetime,
    32817 AS drug_type_concept_id,
    NULL AS stop_reason,
    NULL AS refills,
    -- quantity = 투여량 x 투여횟수
    CASE 
      WHEN u.dose_amount IS NULL OR u.dose_frequency IS NULL THEN NULL
      ELSE TRY_CONVERT(float, u.dose_amount * u.dose_frequency)
    END AS quantity,
    u.days_supply,
    NULL AS sig,
    NULL AS route_concept_id,
    NULL AS lot_number,
    NULL AS provider_id,
    u.visit_occurrence_id,
    NULL AS visit_detail_id,
    u.drug_source_value,
    COALESCE(dm.source_concept_id, hm.source_concept_id) AS drug_source_concept_id,
    NULL AS route_source_value,
    NULL AS dose_unit_source_value
  FROM unioned u
  LEFT JOIN drug_map dm ON dm.code_norm = u.normalized_code
  LEFT JOIN hira_map hm ON hm.code_norm = u.normalized_code
)

-- 신규만 삽입
INSERT INTO [$(CdmSchema)].[drug_exposure](
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
SELECT v.person_id,
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
FROM final_enriched v;



