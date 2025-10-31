SET NOCOUNT ON;

IF OBJECT_ID('$(StagingSchema).drug_vocabulary_map','U') IS NOT NULL
  DROP TABLE [$(StagingSchema)].[drug_vocabulary_map];

CREATE TABLE [$(StagingSchema)].drug_vocabulary_map (
  source_code nvarchar(200),
  source_name nvarchar(500),
  target_concept_id int,
  source_concept_id int
);
