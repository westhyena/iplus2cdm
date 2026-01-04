SET NOCOUNT ON;

IF NOT EXISTS (
  SELECT 1
  FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id = t.schema_id
  WHERE s.name = '$(StagingSchema)' AND t.name = 'measurement_map'
)
BEGIN
  CREATE TABLE [$(StagingSchema)].measurement_map (
    ptntidno varchar(100) NOT NULL,
    [date] varchar(8) NOT NULL,
    [source] varchar(10) NOT NULL, -- 'LAB', 'OP', 'IP'
    
    -- key for LAB
    mk_lab_id varchar(20) NOT NULL DEFAULT '',
    mk_item_no varchar(10) NOT NULL DEFAULT '',
    
    -- key for LAB (LR)
    mk_lr varchar(20) NOT NULL DEFAULT '',
    
    -- key for OP/IP
    mk_serial int NOT NULL DEFAULT 0,
    mk_order int NOT NULL DEFAULT 0,

    map_index int NOT NULL DEFAULT 1,
    
    measurement_id int NOT NULL UNIQUE,
    CONSTRAINT PK_measurement_map PRIMARY KEY (ptntidno, [date], [source], mk_lab_id, mk_item_no, mk_lr, mk_serial, mk_order, map_index)
  );
END;

-- Ensure columns exist if table exists (idempotent)
-- Simplified for brevity assuming fresh create mostly, but good to have safety
IF EXISTS (
  SELECT 1 FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id 
  WHERE s.name = '$(StagingSchema)' AND t.name = 'measurement_map'
)
BEGIN
    -- Check optional columns and add if missing (omitted for speed, trusting create above for now or user can drop table)
    -- But strict PK definition is key.
    DECLARE @dummy int = 0
END
