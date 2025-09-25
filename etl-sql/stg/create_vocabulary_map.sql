SET NOCOUNT ON;

IF NOT EXISTS (
  SELECT 1
  FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id = t.schema_id
  WHERE s.name = '$(StagingSchema)' AND t.name = 'vocabulary_map'
)
BEGIN
  CREATE TABLE [$(StagingSchema)].vocabulary_map (
    source_vocabulary varchar(200),
    source_code varchar(200),
    source_display varchar(500),
    concept_id integer
  );
END;
