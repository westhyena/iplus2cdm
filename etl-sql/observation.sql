SET NOCOUNT ON;

-- observation_id 자동증가: 시퀀스와 기본값 보장
BEGIN TRY
  BEGIN TRAN;

  -- 1) 시퀀스 없으면 생성
  IF NOT EXISTS (
    SELECT 1
    FROM sys.sequences sq
    JOIN sys.schemas sc ON sc.schema_id = sq.schema_id
    WHERE sq.name = 'seq_observation_id' AND sc.name = '$(CdmSchema)'
  )
  BEGIN
    EXEC('CREATE SEQUENCE [$(CdmSchema)].[seq_observation_id] AS INT START WITH 1 INCREMENT BY 1');
  END;

  -- 2) 현재 MAX + 1로 RESTART (기존 데이터 고려)
  DECLARE @max_observation_id INT = ISNULL((SELECT MAX(observation_id) FROM [$(CdmSchema)].[observation]), 0);
  DECLARE @restart_observation_sql nvarchar(400) = N'ALTER SEQUENCE [$(CdmSchema)].[seq_observation_id] RESTART WITH ' + CAST(@max_observation_id + 1 AS nvarchar(20));
  EXEC(@restart_observation_sql);

  -- 3) 컬럼에 기본값(시퀀스) 없으면 추가
  IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.default_object_id = dc.object_id
    JOIN sys.tables t ON t.object_id = c.object_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = '$(CdmSchema)'
      AND t.name = 'observation'
      AND c.name = 'observation_id'
  )
  BEGIN
    ALTER TABLE [$(CdmSchema)].[observation]
      ADD CONSTRAINT DF_observation_id_seq
      DEFAULT (NEXT VALUE FOR [$(CdmSchema)].[seq_observation_id]) FOR observation_id;
  END;

  COMMIT;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK;
  THROW;
END CATCH

-- 공통/소스 CTE
;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), visit_map AS (
  SELECT ptntidno, [date], [source], visit_occurrence_id FROM [$(StagingSchema)].visit_occurrence_map
), hira_observation_map AS (
  -- HIRA 매핑: TARGET_DOMAIN_ID = 'Observation' 인 경우만 사용, 무효 제외
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(m.LOCAL_CD1 AS varchar(200))))) AS code_norm,
    TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) AS target_concept_id,
    TRY_CONVERT(int, m.SOURCE_CONCEPT_ID)   AS source_concept_id
  FROM [$(StagingSchema)].hira_map m
  WHERE m.TARGET_DOMAIN_ID = 'Observation'
    AND m.INVALID_REASON IS NULL
    AND TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) IS NOT NULL
), obs_code_meta AS (
  -- 코드 마스터(PICMECHM)에서 코드별 보험/수익 분류 보조 정보 (9999 임시값)
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(200))))) AS code_norm,
    TRY_CONVERT(int, p.[보험분류]) AS 보험분류,
    TRY_CONVERT(int, p.[수익분류]) AS 수익분류
  FROM [$(SrcSchema)].[PICMECHM] p
  WHERE (
    TRY_CONVERT(int, p.[보험분류]) IN (9999)
    OR TRY_CONVERT(int, p.[수익분류]) IN (9999)
  )
  AND TRY_CONVERT(int, p.[수가분류]) <> 3
), op_raw AS (
  -- 외래(OCSSLIP) 원본
  SELECT
    o.PTNTIDNO,
    o.[진료일자] AS svc_date,
    o.[청구코드] AS claim_code
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, o.[진료일자]) IS NOT NULL
), ip_raw AS (
  -- 입원(OCSSLIPI) 원본
  SELECT
    i.PTNTIDNO,
    i.[진료일자] AS svc_date,
    i.[청구코드] AS claim_code
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, i.[진료일자]) IS NOT NULL
), op_filtered AS (
  -- 후보 선별: HIRA(Observation) 매핑 또는 PICMECHM 9999 분류 포함
  SELECT r.*
  FROM op_raw r
  WHERE 
    EXISTS (
      SELECT 1 FROM hira_observation_map hm 
      WHERE hm.code_norm = UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200)))))
    )
    OR EXISTS (
      SELECT 1 FROM obs_code_meta pm
      WHERE pm.code_norm = UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200)))))
    )
), ip_filtered AS (
  SELECT r.*
  FROM ip_raw r
  WHERE 
    EXISTS (
      SELECT 1 FROM hira_observation_map hm 
      WHERE hm.code_norm = UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200)))))
    )
    OR EXISTS (
      SELECT 1 FROM obs_code_meta pm
      WHERE pm.code_norm = UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200)))))
    )
), op_enriched AS (
  SELECT
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.svc_date) AS observation_date,
    NULL AS observation_datetime,
    CAST(r.claim_code AS varchar(50)) AS observation_source_value,
    UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200))))) AS normalized_code,
    'OP' AS src
  FROM op_filtered r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map vm ON vm.ptntidno = r.PTNTIDNO AND vm.[date] = REPLACE(r.svc_date, '-', '') AND vm.[source] = 'OP'
), ip_enriched AS (
  SELECT
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.svc_date) AS observation_date,
    NULL AS observation_datetime,
    CAST(r.claim_code AS varchar(50)) AS observation_source_value,
    UPPER(LTRIM(RTRIM(CAST(r.claim_code AS varchar(200))))) AS normalized_code,
    'IP' AS src
  FROM ip_filtered r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map vm ON vm.ptntidno = r.PTNTIDNO AND vm.[date] = REPLACE(r.svc_date, '-', '') AND vm.[source] = 'IP'
), unioned AS (
  SELECT * FROM op_enriched
  UNION ALL
  SELECT * FROM ip_enriched
), final_enriched AS (
  SELECT
    u.person_id,
    COALESCE(hm.target_concept_id, 0) AS observation_concept_id,
    u.observation_date,
    u.observation_datetime,
    32817 AS observation_type_concept_id,
    NULL AS value_as_number,
    NULL AS value_as_string,
    NULL AS value_as_concept_id,
    NULL AS qualifier_concept_id,
    NULL AS unit_concept_id,
    NULL AS provider_id,
    u.visit_occurrence_id,
    NULL AS visit_detail_id,
    u.observation_source_value,
    hm.source_concept_id AS observation_source_concept_id,
    NULL AS unit_source_value,
    NULL AS qualifier_source_value,
    NULL AS value_source_value,
    NULL AS observation_event_id,
    NULL AS obs_event_field_concept_id
  FROM unioned u
  LEFT JOIN hira_observation_map hm ON hm.code_norm = u.normalized_code
)

-- 신규만 삽입 (ID는 DEFAULT 제약으로 시퀀스 사용)
INSERT INTO [$(CdmSchema)].[observation] (
  person_id,
  observation_concept_id,
  observation_date,
  observation_datetime,
  observation_type_concept_id,
  value_as_number,
  value_as_string,
  value_as_concept_id,
  qualifier_concept_id,
  unit_concept_id,
  provider_id,
  visit_occurrence_id,
  visit_detail_id,
  observation_source_value,
  observation_source_concept_id,
  unit_source_value,
  qualifier_source_value,
  value_source_value,
  observation_event_id,
  obs_event_field_concept_id
)
SELECT v.person_id,
       v.observation_concept_id,
       v.observation_date,
       v.observation_datetime,
       v.observation_type_concept_id,
       v.value_as_number,
       v.value_as_string,
       v.value_as_concept_id,
       v.qualifier_concept_id,
       v.unit_concept_id,
       v.provider_id,
       v.visit_occurrence_id,
       v.visit_detail_id,
       v.observation_source_value,
       v.observation_source_concept_id,
       v.unit_source_value,
       v.qualifier_source_value,
       v.value_source_value,
       v.observation_event_id,
       v.obs_event_field_concept_id
FROM final_enriched v;



