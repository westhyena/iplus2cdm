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
    mk_lr varchar(20) NOT NULL DEFAULT '',
    mk_seq varchar(10) NOT NULL DEFAULT '', -- Added for SEQ
    
    -- key for OP/IP
    mk_serial int NOT NULL DEFAULT 0,
    mk_order int NOT NULL DEFAULT 0,

    map_index int NOT NULL DEFAULT 1,
    
    measurement_id int NOT NULL UNIQUE,
    CONSTRAINT PK_measurement_map PRIMARY KEY (ptntidno, [date], [source], mk_lab_id, mk_item_no, mk_lr, mk_seq, mk_serial, mk_order, map_index)
  );
END;

-- Explicitly handle schema update for existing table
IF EXISTS (
  SELECT 1 FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id 
  WHERE s.name = '$(StagingSchema)' AND t.name = 'measurement_map'
)
BEGIN
   -- 1. Add mk_seq if not exists
   IF NOT EXISTS (
     SELECT 1 FROM sys.columns c 
     JOIN sys.tables t ON t.object_id = c.object_id
     JOIN sys.schemas s ON s.schema_id = t.schema_id
     WHERE s.name = '$(StagingSchema)' AND t.name = 'measurement_map' AND c.name = 'mk_seq'
   )
   BEGIN
     -- Drop PK first if it exists to allow adding column to PK (requires recreating PK)
     IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_measurement_map' AND parent_object_id = OBJECT_ID('$(StagingSchema).measurement_map'))
     BEGIN
        ALTER TABLE [$(StagingSchema)].measurement_map DROP CONSTRAINT PK_measurement_map;
     END
     
     ALTER TABLE [$(StagingSchema)].measurement_map ADD mk_seq varchar(10) NOT NULL CONSTRAINT DF_measurement_map_seq DEFAULT '' WITH VALUES;
     
     -- Recreate PK with new column
     ALTER TABLE [$(StagingSchema)].measurement_map ADD CONSTRAINT PK_measurement_map PRIMARY KEY (ptntidno, [date], [source], mk_lab_id, mk_item_no, mk_lr, mk_seq, mk_serial, mk_order, map_index);
   END
END
