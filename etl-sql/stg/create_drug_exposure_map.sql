SET NOCOUNT ON;

IF NOT EXISTS (
  SELECT 1
  FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id = t.schema_id
  WHERE s.name = '$(StagingSchema)' AND t.name = 'drug_exposure_map'
)
BEGIN
  CREATE TABLE [$(StagingSchema)].drug_exposure_map (
    ptntidno varchar(100) NOT NULL,
    [date] varchar(8) NOT NULL,
    [source] varchar(2) NOT NULL,
    serial_no int NOT NULL,
    order_no int NOT NULL,
    drug_exposure_id int NOT NULL UNIQUE,
    CONSTRAINT PK_drug_exposure_map PRIMARY KEY (ptntidno, [date], [source], serial_no, order_no)
  );
END;

-- 기존 테이블이 있을 경우 스키마 보정: serial_no 추가 및 PK 재정의
IF EXISTS (
  SELECT 1
  FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id = t.schema_id
  WHERE s.name = '$(StagingSchema)' AND t.name = 'drug_exposure_map'
)
BEGIN
  -- serial_no 컬럼 없으면 추가 (IP는 0으로 세팅)
  IF NOT EXISTS (
    SELECT 1 FROM sys.columns c
    JOIN sys.tables t ON t.object_id = c.object_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = '$(StagingSchema)' AND t.name = 'drug_exposure_map' AND c.name = 'serial_no'
  )
  BEGIN
    ALTER TABLE [$(StagingSchema)].drug_exposure_map
      ADD serial_no int NOT NULL CONSTRAINT DF_drug_exposure_map_serial DEFAULT (0) WITH VALUES;
  END;

  -- PK를 (ptntidno,date,source,serial_no,order_no)로 재정의
  IF EXISTS (
    SELECT 1 FROM sys.key_constraints kc
    JOIN sys.tables t ON t.object_id = kc.parent_object_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE kc.[name] = 'PK_drug_exposure_map'
      AND s.name = '$(StagingSchema)' AND t.name = 'drug_exposure_map'
  )
  BEGIN
    ALTER TABLE [$(StagingSchema)].drug_exposure_map DROP CONSTRAINT PK_drug_exposure_map;
  END;
  ALTER TABLE [$(StagingSchema)].drug_exposure_map
    ADD CONSTRAINT PK_drug_exposure_map PRIMARY KEY (ptntidno, [date], [source], serial_no, order_no);
END;


