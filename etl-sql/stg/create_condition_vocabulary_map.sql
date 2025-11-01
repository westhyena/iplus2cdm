SET NOCOUNT ON;

IF OBJECT_ID('$(StagingSchema).condition_vocabulary_map','U') IS NOT NULL
  DROP TABLE [$(StagingSchema)].[condition_vocabulary_map];

CREATE TABLE [$(StagingSchema)].condition_vocabulary_map (
  source_code nvarchar(200),
  name nvarchar(500),
  target_concept_id int,
  source_concept_id int
);

-- 스테이징 테이블은 동적 생성 (scripts/modules/condition-map.ps1)
