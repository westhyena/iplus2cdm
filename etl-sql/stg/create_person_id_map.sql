SET NOCOUNT ON;

IF NOT EXISTS (
  SELECT 1
  FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id = t.schema_id
  WHERE s.name = '$(StagingSchema)' AND t.name = 'person_id_map'
)
BEGIN
  CREATE TABLE [$(StagingSchema)].person_id_map (
    ptntidno varchar(100) NOT NULL PRIMARY KEY,
    person_id int NOT NULL UNIQUE
  );
END;
