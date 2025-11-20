SET NOCOUNT ON;

IF NOT EXISTS (
  SELECT 1
  FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id = t.schema_id
  WHERE s.name = '$(StagingSchema)' AND t.name = 'device_exposure_map'
)
BEGIN
  CREATE TABLE [$(StagingSchema)].device_exposure_map (
    ptntidno varchar(100) NOT NULL,
    [date] varchar(8) NOT NULL,
    [source] varchar(2) NOT NULL,
    order_no int NOT NULL,
    device_exposure_id int NOT NULL UNIQUE,
    CONSTRAINT PK_device_exposure_map PRIMARY KEY (ptntidno, [date], [source], order_no)
  );
END;


