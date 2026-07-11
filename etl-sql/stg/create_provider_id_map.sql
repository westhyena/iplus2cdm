SET NOCOUNT ON;

IF NOT EXISTS (
  SELECT 1
  FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id = t.schema_id
  WHERE s.name = '$(StagingSchema)' AND t.name = 'provider_id_map'
)
BEGIN
  CREATE TABLE [$(StagingSchema)].provider_id_map (
    userid varchar(100) NOT NULL PRIMARY KEY,
    provider_id int NOT NULL UNIQUE
  );
END;
