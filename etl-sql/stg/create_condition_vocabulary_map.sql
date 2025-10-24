SET NOCOUNT ON;

IF OBJECT_ID('$(StagingSchema).condition_vocabulary_map','U') IS NOT NULL
  DROP TABLE [$(StagingSchema)].[condition_vocabulary_map];

CREATE TABLE [$(StagingSchema)].condition_vocabulary_map (
  source_code nvarchar(200),
  kor_name nvarchar(500),
  eng_name nvarchar(500),
  concept_id int
);

-- 스테이징 적재용 테이블 (CSV 원본 문자형으로 수용)
IF OBJECT_ID('$(StagingSchema).condition_vocabulary_map_stage','U') IS NOT NULL
  DROP TABLE [$(StagingSchema)].[condition_vocabulary_map_stage];

CREATE TABLE [$(StagingSchema)].condition_vocabulary_map_stage (
  source_code nvarchar(4000) NULL,
  kor_name nvarchar(4000) NULL,
  eng_name nvarchar(4000) NULL,
  concept_id nvarchar(100) NULL
);
