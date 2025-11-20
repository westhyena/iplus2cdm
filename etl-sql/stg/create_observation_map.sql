SET NOCOUNT ON;

IF NOT EXISTS (
  SELECT 1
  FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id = t.schema_id
  WHERE s.name = '$(StagingSchema)' AND t.name = 'observation_map'
)
BEGIN
  CREATE TABLE [$(StagingSchema)].observation_map (
    ptntidno varchar(100) NOT NULL,
    [date] varchar(8) NOT NULL,
    [source] varchar(2) NOT NULL,
    order_no int NOT NULL,
    observation_id int NOT NULL UNIQUE,
    CONSTRAINT PK_observation_map PRIMARY KEY (ptntidno, [date], [source], order_no)
  );
END;


