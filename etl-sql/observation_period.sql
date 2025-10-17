SET NOCOUNT ON;

-- observation_period_id 자동증가: 시퀀스와 기본값 보장
BEGIN TRY
  BEGIN TRAN;

  -- 1) 시퀀스 없으면 생성
  IF NOT EXISTS (
    SELECT 1
    FROM sys.sequences sq
    JOIN sys.schemas sc ON sc.schema_id = sq.schema_id
    WHERE sq.name = 'seq_observation_period_id' AND sc.name = '$(CdmSchema)'
  )
  BEGIN
    EXEC('CREATE SEQUENCE [$(CdmSchema)].[seq_observation_period_id] AS INT START WITH 1 INCREMENT BY 1');
  END;

  -- 2) 현재 MAX + 1로 RESTART (기존 데이터 고려)
  DECLARE @max_id INT = ISNULL((SELECT MAX(observation_period_id) FROM [$(CdmSchema)].[observation_period]), 0);
  DECLARE @restart_sql nvarchar(400) = N'ALTER SEQUENCE [$(CdmSchema)].[seq_observation_period_id] RESTART WITH ' + CAST(@max_id + 1 AS nvarchar(20));
  EXEC(@restart_sql);

  -- 3) 컬럼에 기본값(시퀀스) 없으면 추가
  IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.default_object_id = dc.object_id
    JOIN sys.tables t ON t.object_id = c.object_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = '$(CdmSchema)'
      AND t.name = 'observation_period'
      AND c.name = 'observation_period_id'
  )
  BEGIN
    ALTER TABLE [$(CdmSchema)].[observation_period]
      ADD CONSTRAINT DF_observation_period_id_seq
      DEFAULT (NEXT VALUE FOR [$(CdmSchema)].[seq_observation_period_id]) FOR observation_period_id;
  END;

  COMMIT;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK;
  THROW;
END CATCH

-- 공통 CTE: 각 person의 첫 방문일, 마지막 방문일 산출
;WITH first_last_visit AS (
  SELECT
    vo.person_id,
    MIN(vo.visit_start_date) AS first_visit_date,
    MAX(vo.visit_end_date)   AS last_visit_date
  FROM [$(CdmSchema)].visit_occurrence vo
  GROUP BY vo.person_id
), candidate AS (
  SELECT
    p.person_id,
    -- 방문이 있는 경우: 첫 방문 ~ 마지막 방문
    flv.first_visit_date AS observation_period_start_date,
    flv.last_visit_date  AS observation_period_end_date,
    32818 AS period_type_concept_id
  FROM [$(CdmSchema)].person p
  LEFT JOIN first_last_visit flv ON flv.person_id = p.person_id
)

-- 신규만 삽입: 방문 없는 사람은 생성 제외
INSERT INTO [$(CdmSchema)].[observation_period](
  person_id,
  observation_period_start_date,
  observation_period_end_date,
  period_type_concept_id
)
SELECT c.person_id,
       c.observation_period_start_date,
       c.observation_period_end_date,
       c.period_type_concept_id
FROM candidate c
WHERE c.observation_period_start_date IS NOT NULL
  AND c.observation_period_end_date   IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM [$(CdmSchema)].[observation_period] t
    WHERE t.person_id = c.person_id
  );



