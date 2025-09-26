SET NOCOUNT ON;

IF NOT EXISTS (
  SELECT 1
  FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id = t.schema_id
  WHERE s.name = '$(StagingSchema)' AND t.name = 'visit_occurrence_map'
)
BEGIN
  CREATE TABLE [$(StagingSchema)].visit_occurrence_map (
    ptntidno varchar(100) NOT NULL,
    [date] varchar(8) NOT NULL,
    [source] varchar(2) NOT NULL,
    visit_occurrence_id int NOT NULL UNIQUE,
    CONSTRAINT PK_visit_occurrence_map PRIMARY KEY (ptntidno, [date], [source])
  );
END;
