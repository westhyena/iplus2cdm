SET NOCOUNT ON;

-- cost_id 자동증가: 시퀀스와 기본값 보장
BEGIN TRY
  BEGIN TRAN;

  -- 1) 시퀀스 없으면 생성
  IF NOT EXISTS (
    SELECT 1
    FROM sys.sequences sq
    JOIN sys.schemas sc ON sc.schema_id = sq.schema_id
    WHERE sq.name = 'seq_cost_id' AND sc.name = '$(CdmSchema)'
  )
  BEGIN
    EXEC('CREATE SEQUENCE [$(CdmSchema)].[seq_cost_id] AS INT START WITH 1 INCREMENT BY 1');
  END;

  -- 2) 현재 MAX + 1로 RESTART (기존 데이터 고려)
  DECLARE @max_cost_id INT = ISNULL((SELECT MAX(cost_id) FROM [$(CdmSchema)].[cost]), 0);
  DECLARE @restart_cost_sql nvarchar(400) = N'ALTER SEQUENCE [$(CdmSchema)].[seq_cost_id] RESTART WITH ' + CAST(@max_cost_id + 1 AS nvarchar(20));
  EXEC(@restart_cost_sql);

  -- 3) 컬럼에 기본값(시퀀스) 없으면 추가
  IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.default_object_id = dc.object_id
    JOIN sys.tables t ON t.object_id = c.object_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = '$(CdmSchema)'
      AND t.name = 'cost'
      AND c.name = 'cost_id'
  )
  BEGIN
    ALTER TABLE [$(CdmSchema)].[cost]
      ADD CONSTRAINT DF_cost_id_seq
      DEFAULT (NEXT VALUE FOR [$(CdmSchema)].[seq_cost_id]) FOR cost_id;
  END;

  COMMIT;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK;
  THROW;
END CATCH;

-- OCSSLIP/OCSSLIPI의 '금액'을 cost.total_cost로 적재 (procedure_occurrence 기준)
;WITH keys_map AS (
  SELECT ptntidno, [date], [source], serial_no, order_no, map_index, procedure_occurrence_id
  FROM [$(StagingSchema)].procedure_occurrence_map
), op_raw AS (
  SELECT
    o.PTNTIDNO            AS k_ptntidno,
    REPLACE(o.[진료일자], '-', '') AS k_date,
    'OP'                  AS k_source,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),''))   AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, o.[진료일자]) IS NOT NULL
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),'')) IS NOT NULL
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),'')) IS NOT NULL
), ip_raw AS (
  SELECT
    i.PTNTIDNO            AS k_ptntidno,
    REPLACE(i.[진료일자], '-', '') AS k_date,
    'IP'                  AS k_source,
    0                     AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, i.[진료일자]) IS NOT NULL
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),'')) IS NOT NULL
), unioned AS (
  SELECT * FROM op_raw
  UNION ALL
  SELECT * FROM ip_raw
), joined AS (
  -- procedure_occurrence_map과 조인하여 대상 event_id 확보
  -- 중복 방지를 위해 map_index = 1 우선 매핑 사용
  SELECT
    km.procedure_occurrence_id AS cost_event_id,
    u.amount
  FROM unioned u
  JOIN keys_map km
    ON km.ptntidno = u.k_ptntidno
   AND km.[date]   = u.k_date
   AND km.[source] = u.k_source
   AND km.serial_no = u.k_serial_no
   AND km.order_no  = u.k_order_no
   AND km.map_index = 1
  WHERE u.amount IS NOT NULL
    AND u.amount <> 0
)
INSERT INTO [$(CdmSchema)].[cost] (
  cost_event_id,
  cost_domain_id,
  cost_type_concept_id,
  currency_concept_id,
  total_cost
)
SELECT
  j.cost_event_id,
  'Procedure' AS cost_domain_id,
  32817       AS cost_type_concept_id,
  44818598    AS currency_concept_id, -- KRW
  j.amount    AS total_cost
FROM joined j
WHERE NOT EXISTS (
  SELECT 1
  FROM [$(CdmSchema)].[cost] c
  WHERE c.cost_event_id = j.cost_event_id
    AND c.cost_domain_id = 'Procedure'
    AND c.cost_type_concept_id = 32817
);

-- Drug: OCSSLIP/OCSSLIPI의 '금액'을 drug_exposure 기반으로 cost.total_cost 적재
;WITH keys_map AS (
  SELECT ptntidno, [date], [source], serial_no, order_no, map_index, drug_exposure_id
  FROM [$(StagingSchema)].drug_exposure_map
), op_raw AS (
  SELECT
    o.PTNTIDNO            AS k_ptntidno,
    REPLACE(o.[진료일자], '-', '') AS k_date,
    'OP'                  AS k_source,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),''))   AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, o.[진료일자]) IS NOT NULL
), ip_raw AS (
  SELECT
    i.PTNTIDNO            AS k_ptntidno,
    REPLACE(i.[진료일자], '-', '') AS k_date,
    'IP'                  AS k_source,
    0                     AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, i.[진료일자]) IS NOT NULL
), unioned AS (
  SELECT * FROM op_raw
  UNION ALL
  SELECT * FROM ip_raw
), joined AS (
  SELECT
    km.drug_exposure_id AS cost_event_id,
    u.amount
  FROM unioned u
  JOIN keys_map km
    ON km.ptntidno = u.k_ptntidno
   AND km.[date]   = u.k_date
   AND km.[source] = u.k_source
   AND km.serial_no = u.k_serial_no
   AND km.order_no  = u.k_order_no
   AND km.map_index = 1
  WHERE u.amount IS NOT NULL
    AND u.amount <> 0
)
INSERT INTO [$(CdmSchema)].[cost] (
  cost_event_id,
  cost_domain_id,
  cost_type_concept_id,
  currency_concept_id,
  total_cost
)
SELECT
  j.cost_event_id,
  'Drug' AS cost_domain_id,
  32817  AS cost_type_concept_id,
  44818598 AS currency_concept_id,
  j.amount AS total_cost
FROM joined j
WHERE NOT EXISTS (
  SELECT 1
  FROM [$(CdmSchema)].[cost] c
  WHERE c.cost_event_id = j.cost_event_id
    AND c.cost_domain_id = 'Drug'
    AND c.cost_type_concept_id = 32817
);

-- Device: OCSSLIP/OCSSLIPI의 '금액'을 device_exposure 기반으로 cost.total_cost 적재
;WITH keys_map AS (
  SELECT ptntidno, [date], [source], serial_no, order_no, map_index, device_exposure_id
  FROM [$(StagingSchema)].device_exposure_map
), op_raw AS (
  SELECT
    o.PTNTIDNO            AS k_ptntidno,
    REPLACE(o.[진료일자], '-', '') AS k_date,
    'OP'                  AS k_source,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),''))   AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, o.[진료일자]) IS NOT NULL
), ip_raw AS (
  SELECT
    i.PTNTIDNO            AS k_ptntidno,
    REPLACE(i.[진료일자], '-', '') AS k_date,
    'IP'                  AS k_source,
    0                     AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, i.[진료일자]) IS NOT NULL
), unioned AS (
  SELECT * FROM op_raw
  UNION ALL
  SELECT * FROM ip_raw
), joined AS (
  SELECT
    km.device_exposure_id AS cost_event_id,
    u.amount
  FROM unioned u
  JOIN keys_map km
    ON km.ptntidno = u.k_ptntidno
   AND km.[date]   = u.k_date
   AND km.[source] = u.k_source
   AND km.serial_no = u.k_serial_no
   AND km.order_no  = u.k_order_no
   AND km.map_index = 1
  WHERE u.amount IS NOT NULL
    AND u.amount <> 0
)
INSERT INTO [$(CdmSchema)].[cost] (
  cost_event_id,
  cost_domain_id,
  cost_type_concept_id,
  currency_concept_id,
  total_cost
)
SELECT
  j.cost_event_id,
  'Device' AS cost_domain_id,
  32817    AS cost_type_concept_id,
  44818598 AS currency_concept_id,
  j.amount AS total_cost
FROM joined j
WHERE NOT EXISTS (
  SELECT 1
  FROM [$(CdmSchema)].[cost] c
  WHERE c.cost_event_id = j.cost_event_id
    AND c.cost_domain_id = 'Device'
    AND c.cost_type_concept_id = 32817
);

-- Observation: OCSSLIP/OCSSLIPI의 '금액'을 observation 기반으로 cost.total_cost 적재
;WITH keys_map AS (
  SELECT ptntidno, [date], [source], serial_no, order_no, map_index, observation_id
  FROM [$(StagingSchema)].observation_map
), op_raw AS (
  SELECT
    o.PTNTIDNO            AS k_ptntidno,
    REPLACE(o.[진료일자], '-', '') AS k_date,
    'OP'                  AS k_source,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),''))   AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, o.[진료일자]) IS NOT NULL
), ip_raw AS (
  SELECT
    i.PTNTIDNO            AS k_ptntidno,
    REPLACE(i.[진료일자], '-', '') AS k_date,
    'IP'                  AS k_source,
    0                     AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),'')) AS amount
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, i.[진료일자]) IS NOT NULL
), unioned AS (
  SELECT * FROM op_raw
  UNION ALL
  SELECT * FROM ip_raw
), joined AS (
  SELECT
    km.observation_id AS cost_event_id,
    u.amount
  FROM unioned u
  JOIN keys_map km
    ON km.ptntidno = u.k_ptntidno
   AND km.[date]   = u.k_date
   AND km.[source] = u.k_source
   AND km.serial_no = u.k_serial_no
   AND km.order_no  = u.k_order_no
   AND km.map_index = 1
  WHERE u.amount IS NOT NULL
    AND u.amount <> 0
)
INSERT INTO [$(CdmSchema)].[cost] (
  cost_event_id,
  cost_domain_id,
  cost_type_concept_id,
  currency_concept_id,
  total_cost
)
SELECT
  j.cost_event_id,
  'Observation' AS cost_domain_id,
  32817         AS cost_type_concept_id,
  44818598      AS currency_concept_id,
  j.amount      AS total_cost
FROM joined j
WHERE NOT EXISTS (
  SELECT 1
  FROM [$(CdmSchema)].[cost] c
  WHERE c.cost_event_id = j.cost_event_id
    AND c.cost_domain_id = 'Observation'
    AND c.cost_type_concept_id = 32817
);


