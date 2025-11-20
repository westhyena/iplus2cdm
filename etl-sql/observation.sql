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

-- 소스키 매핑(observation_map) 신규 추가
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
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),'')) IS NOT NULL
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),'')) IS NOT NULL
    AND (
      EXISTS (
        SELECT 1
        FROM [$(StagingSchema)].hira_map hm
        WHERE hm.TARGET_DOMAIN_ID = 'Observation'
          AND hm.INVALID_REASON IS NULL
          AND UPPER(LTRIM(RTRIM(CAST(hm.LOCAL_CD1 AS varchar(200))))) = UPPER(LTRIM(RTRIM(CAST(o.[청구코드] AS varchar(200)))))
          AND TRY_CONVERT(int, hm.TARGET_CONCEPT_ID_1) IS NOT NULL
      )
      OR EXISTS (
        SELECT 1
        FROM [$(SrcSchema)].[PICMECHM] p
        WHERE UPPER(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(200))))) = UPPER(LTRIM(RTRIM(CAST(o.[청구코드] AS varchar(200)))))
          AND (
            TRY_CONVERT(int, p.[보험분류]) IN (9999)
            OR TRY_CONVERT(int, p.[수익분류]) IN (9999)
          )
          AND TRY_CONVERT(int, p.[수가분류]) <> 3
      )
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
      EXISTS (
        SELECT 1
        FROM [$(StagingSchema)].hira_map hm
        WHERE hm.TARGET_DOMAIN_ID = 'Observation'
          AND hm.INVALID_REASON IS NULL
          AND UPPER(LTRIM(RTRIM(CAST(hm.LOCAL_CD1 AS varchar(200))))) = UPPER(LTRIM(RTRIM(CAST(i.[청구코드] AS varchar(200)))))
          AND TRY_CONVERT(int, hm.TARGET_CONCEPT_ID_1) IS NOT NULL
      )
      OR EXISTS (
        SELECT 1
        FROM [$(SrcSchema)].[PICMECHM] p
        WHERE UPPER(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(200))))) = UPPER(LTRIM(RTRIM(CAST(i.[청구코드] AS varchar(200)))))
          AND (
            TRY_CONVERT(int, p.[보험분류]) IN (9999)
            OR TRY_CONVERT(int, p.[수익분류]) IN (9999)
          )
          AND TRY_CONVERT(int, p.[수가분류]) <> 3
      )
    )
), hira_obs_codes AS (
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(m.LOCAL_CD1 AS varchar(200))))) AS code_norm
  FROM [$(StagingSchema)].hira_map m
  WHERE m.TARGET_DOMAIN_ID = 'Observation'
    AND m.INVALID_REASON IS NULL
    AND TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) IS NOT NULL
), src_mapped AS (
  SELECT 
    s.ptntidno, s.[date], s.[source], s.serial_no, s.order_no,
    ROW_NUMBER() OVER (
      PARTITION BY s.ptntidno, s.[date], s.[source], s.serial_no, s.order_no
      ORDER BY (CASE WHEN c.code_norm IS NULL THEN 1 ELSE 0 END), s.claim_code_norm
    ) AS map_index
  FROM src_keys s
  LEFT JOIN hira_obs_codes c ON c.code_norm = s.claim_code_norm
)
INSERT INTO  [$(StagingSchema)].observation_map (
    ptntidno, [date], [source], serial_no, order_no, map_index, observation_id)
SELECT k.ptntidno,
       k.[date],
       k.[source],
       k.serial_no,
       k.order_no,
       k.map_index,
       x.base_id + ROW_NUMBER() OVER (ORDER BY k.[date], k.order_no, k.map_index)
FROM src_mapped k
CROSS JOIN (
  SELECT ISNULL(MAX(observation_id),0) AS base_id
  FROM   [$(StagingSchema)].observation_map
) x
LEFT JOIN [$(StagingSchema)].observation_map m
  ON  m.ptntidno = k.ptntidno
  AND m.[date] = k.[date]
  AND m.[source] = k.[source]
  AND m.serial_no = k.serial_no
  AND m.order_no = k.order_no
  AND m.map_index = k.map_index
WHERE m.ptntidno IS NULL;

-- 공통/소스 CTE
;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), visit_map AS (
  SELECT ptntidno, [date], [source], visit_occurrence_id FROM [$(StagingSchema)].visit_occurrence_map
), keys_map AS (
  SELECT ptntidno, [date], [source], serial_no, order_no, map_index, observation_id FROM [$(StagingSchema)].observation_map
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
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),'')) AS serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),'')) AS order_no,
    o.[청구코드] AS claim_code
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, o.[진료일자]) IS NOT NULL
), ip_raw AS (
  -- 입원(OCSSLIPI) 원본
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
    r.PTNTIDNO AS k_ptntidno,
    REPLACE(r.svc_date, '-', '') AS k_date,
    'OP' AS k_source,
    r.serial_no AS k_serial_no,
    r.order_no AS k_order_no,
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
    r.PTNTIDNO AS k_ptntidno,
    REPLACE(r.svc_date, '-', '') AS k_date,
    'IP' AS k_source,
    r.serial_no AS k_serial_no,
    r.order_no AS k_order_no,
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
  LEFT JOIN hira_observation_map hm ON hm.code_norm = u.normalized_code
), final_enriched AS (
  SELECT
    km.observation_id,
    m.person_id,
    COALESCE(m.target_concept_id, 0) AS observation_concept_id,
    m.observation_date,
    m.observation_datetime,
    32817 AS observation_type_concept_id,
    NULL AS value_as_number,
    NULL AS value_as_string,
    NULL AS value_as_concept_id,
    NULL AS qualifier_concept_id,
    NULL AS unit_concept_id,
    NULL AS provider_id,
    m.visit_occurrence_id,
    NULL AS visit_detail_id,
    m.observation_source_value,
    m.source_concept_id AS observation_source_concept_id,
    NULL AS unit_source_value,
    NULL AS qualifier_source_value,
    NULL AS value_source_value,
    NULL AS observation_event_id,
    NULL AS obs_event_field_concept_id
  FROM mapped m
  LEFT JOIN keys_map km 
    ON km.ptntidno = m.k_ptntidno
   AND km.[date] = m.k_date
   AND km.[source] = m.k_source
   AND km.serial_no = m.k_serial_no
   AND km.order_no = m.k_order_no
   AND km.map_index = m.map_index
)

-- 신규만 삽입 (ID는 DEFAULT 제약으로 시퀀스 사용)
INSERT INTO [$(CdmSchema)].[observation] (
  observation_id,
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
SELECT v.observation_id,
       v.person_id,
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
FROM final_enriched v
WHERE NOT EXISTS (
  SELECT 1 FROM [$(CdmSchema)].[observation] t WHERE t.observation_id = v.observation_id
);



