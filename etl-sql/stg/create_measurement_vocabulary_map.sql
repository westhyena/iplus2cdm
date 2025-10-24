SET NOCOUNT ON;

IF OBJECT_ID('$(StagingSchema).measurement_vocabulary_map','U') IS NOT NULL
  DROP TABLE [$(StagingSchema)].[measurement_vocabulary_map];

CREATE TABLE [$(StagingSchema)].measurement_vocabulary_map (
  LABNM nvarchar(500),
  ItemName nvarchar(500),
  common_concept_id int,
  right_concept_id int,
  left_concept_id int
);
