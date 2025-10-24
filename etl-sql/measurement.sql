SET NOCOUNT ON;

-- measurement_id 자동증가: 시퀀스와 기본값 보장
BEGIN TRY
  BEGIN TRAN;

  -- 1) 시퀀스 없으면 생성
  IF NOT EXISTS (
    SELECT 1
    FROM sys.sequences sq
    JOIN sys.schemas sc ON sc.schema_id = sq.schema_id
    WHERE sq.name = 'seq_measurement_id' AND sc.name = '$(CdmSchema)'
  )
  BEGIN
    EXEC('CREATE SEQUENCE [$(CdmSchema)].[seq_measurement_id] AS INT START WITH 1 INCREMENT BY 1');
  END;

  -- 2) 현재 MAX + 1로 RESTART (기존 데이터 고려)
  DECLARE @max_id INT = ISNULL((SELECT MAX(measurement_id) FROM [$(CdmSchema)].[measurement]), 0);
  DECLARE @restart_sql nvarchar(400) = N'ALTER SEQUENCE [$(CdmSchema)].[seq_measurement_id] RESTART WITH ' + CAST(@max_id + 1 AS nvarchar(20));
  EXEC(@restart_sql);

  -- 3) 컬럼에 기본값(시퀀스) 없으면 추가
  IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.default_object_id = dc.object_id
    JOIN sys.tables t ON t.object_id = c.object_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = '$(CdmSchema)' AND t.name = 'measurement' AND c.name = 'measurement_id'
  )
  BEGIN
    ALTER TABLE [$(CdmSchema)].[measurement]
    ADD CONSTRAINT DF_measurement_id_seq
    DEFAULT (NEXT VALUE FOR [$(CdmSchema)].[seq_measurement_id]) FOR measurement_id;
  END;

  COMMIT;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK;
  THROW;
END CATCH;

-- 공통 맵/소스 CTE
;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), visit_map AS (
  SELECT ptntidno, [date], [source], visit_occurrence_id FROM [$(StagingSchema)].visit_occurrence_map
), meas_map AS (
  SELECT
    UPPER(LTRIM(RTRIM(LABNM))) AS LABNM,
    UPPER(LTRIM(RTRIM(ItemName))) AS ItemName,
    common_concept_id,
    right_concept_id,
    left_concept_id
  FROM [$(StagingSchema)].measurement_vocabulary_map
), lab_master AS (
  SELECT 
    m.LABID,
    m.LABNM,
    v.ItemNumber,
    v.ItemName,
    v.Symbol
  FROM
    [$(SrcSchema)].[INFLABM] m
  CROSS APPLY (
    VALUES
      ('Item1', m.Item1, m.Symbol1),
      ('Item2', m.Item2, m.Symbol2),
      ('Item3', m.Item3, m.Symbol3),
      ('Item4', m.Item4, m.Symbol4),
      ('Item5', m.Item5, m.Symbol5),
      ('Item6', m.Item6, m.Symbol6),
      ('Item7', m.Item7, m.Symbol7),
      ('Item8', m.Item8, m.Symbol8),
      ('Item9', m.Item9, m.Symbol9),
      ('Item10', m.Item10, m.Symbol10),
      ('Item11', m.Item11, m.Symbol11),
      ('Item12', m.Item12, m.Symbol12),
      ('Item13', m.Item13, m.Symbol13),
      ('Item14', m.Item14, m.Symbol14),
      ('Item15', m.Item15, m.Symbol15),
      ('Item16', m.Item16, m.Symbol16),
      ('Item17', m.Item17, m.Symbol17),
      ('Item18', m.Item18, m.Symbol18),
      ('Item19', m.Item19, m.Symbol19),
      ('Item20', m.Item20, m.Symbol20),
      ('Item21', m.Item21, m.Symbol21),
      ('Item22', m.Item22, m.Symbol22),
      ('Item23', m.Item23, m.Symbol23),
      ('Item24', m.Item24, m.Symbol24),
      ('Item25', m.Item25, m.Symbol25),
      ('Item26', m.Item26, m.Symbol26),
      ('Item27', m.Item27, m.Symbol27),
      ('Item28', m.Item28, m.Symbol28),
      ('Item29', m.Item29, m.Symbol29),
      ('Item30', m.Item30, m.Symbol30),
      ('Item31', m.Item31, m.Symbol31),
      ('Item32', m.Item32, m.Symbol32),
      ('Item33', m.Item33, m.Symbol33),
      ('Item34', m.Item34, m.Symbol34),
      ('Item35', m.Item35, m.Symbol35),
      ('Item36', m.Item36, m.Symbol36),
      ('Item37', m.Item37, m.Symbol37),
      ('Item38', m.Item38, m.Symbol38),
      ('Item39', m.Item39, m.Symbol39),
      ('Item40', m.Item40, m.Symbol40)
  ) AS v(ItemNumber, ItemName, Symbol)
  WHERE 
    v.ItemName IS NOT NULL
    AND LEN(v.ItemName) > 0
), lab_raw AS (
  SELECT 
    t.PTNTIDNO,
    t.REGDATE,
    t.LABID,
    t.LR,
    v.ItemNumber,
    v.ItemValue
  FROM
    [$(SrcSchema)].[INFLABD] t
  CROSS APPLY (
      VALUES
          -- item 1 to 40
          ('Item1', t.Item1),
          ('Item2', t.Item2),
          ('Item3', t.Item3),
          ('Item4', t.Item4),
          ('Item5', t.Item5),
          ('Item6', t.Item6),
          ('Item7', t.Item7),
          ('Item8', t.Item8),
          ('Item9', t.Item9),
          ('Item10', t.Item10),
          ('Item11', t.Item11),
          ('Item12', t.Item12),
          ('Item13', t.Item13),
          ('Item14', t.Item14),
          ('Item15', t.Item15),
          ('Item16', t.Item16),
          ('Item17', t.Item17),
          ('Item18', t.Item18),
          ('Item19', t.Item19),
          ('Item20', t.Item20),
          ('Item21', t.Item21),
          ('Item22', t.Item22),
          ('Item23', t.Item23),
          ('Item24', t.Item24),
          ('Item25', t.Item25),
          ('Item26', t.Item26),
          ('Item27', t.Item27),
          ('Item28', t.Item28),
          ('Item29', t.Item29),
          ('Item30', t.Item30),
          ('Item31', t.Item31),
          ('Item32', t.Item32),
          ('Item33', t.Item33),
          ('Item34', t.Item34),
          ('Item35', t.Item35),
          ('Item36', t.Item36),
          ('Item37', t.Item37),
          ('Item38', t.Item38),
          ('Item39', t.Item39),
          ('Item40', t.Item40)
  ) AS v(ItemNumber, ItemValue)
), src_enriched AS (
  SELECT  
    pm.person_id,
    COALESCE(
      CASE
        WHEN UPPER(LTRIM(RTRIM(t.LR))) IN ('R','OD','우','RIGHT','RIGHTEYE','RIGHT EYE','OD(우)') THEN mm.left_concept_id
        WHEN UPPER(LTRIM(RTRIM(t.LR))) IN ('L','OS','좌','LEFT','LEFTEYE','LEFT EYE','OS(좌)') THEN mm.right_concept_id
        ELSE mm.common_concept_id
      END,
      mm.common_concept_id,
      0
    ) AS measurement_concept_id,
    TRY_CONVERT(date, t.REGDATE) AS measurement_date,
    NULL AS measurement_datetime,
    NULL AS measurement_time,
    32817 AS measurement_type_concept_id,
    NULL AS operator_concept_id,
    TRY_CAST(REPLACE(t.ItemValue, ' ', '') AS FLOAT) AS value_as_number,
    NULL AS value_as_concept_id,
    NULL AS unit_concept_id,
    NULL AS range_low,
    NULL AS range_high,
    NULL AS provider_id,
    vm.visit_occurrence_id,
    NULL AS visit_detail_id,
    CONCAT(m.LABNM, ' - ', m.ItemName, ' - ', m.Symbol, ' - ', t.LR) AS measurement_source_value,
    NULL AS measurement_source_concept_id,
    NULL AS unit_source_value,
    NULL AS unit_source_concept_id,
    t.ItemValue AS value_source_value,
    NULL AS measurement_event_id,
    NULL AS meas_event_field_concept_id
  FROM lab_raw t
  JOIN lab_master m
    ON
      m.LABID = t.LABID
      AND m.ItemNumber = t.ItemNumber
  LEFT JOIN meas_map mm
    ON UPPER(LTRIM(RTRIM(m.LABNM))) = mm.LABNM
   AND UPPER(LTRIM(RTRIM(m.ItemName))) = mm.ItemName
  JOIN person_map pm
    ON pm.ptntidno = t.PTNTIDNO
  JOIN visit_map vm
    ON vm.ptntidno = t.PTNTIDNO
    AND vm.date = t.REGDATE
    -- source가 정해져있지 않음. 일단 날짜만 맞으면 join
)

-- 신규만 삽입
INSERT INTO [$(CdmSchema)].[measurement](
  person_id,
  measurement_concept_id,
  measurement_date,
  measurement_datetime,
  measurement_time, -- deprecated
  measurement_type_concept_id,
  operator_concept_id,
  value_as_number,
  value_as_concept_id,
  unit_concept_id,
  range_low,
  range_high,
  provider_id,
  visit_occurrence_id,
  visit_detail_id,
  measurement_source_value,
  measurement_source_concept_id,
  unit_source_value,
  unit_source_concept_id,
  value_source_value,
  measurement_event_id,
  meas_event_field_concept_id
)
SELECT m.person_id,
       m.measurement_concept_id,
       m.measurement_date,
       m.measurement_datetime,
       m.measurement_time, -- deprecated
       m.measurement_type_concept_id,
       m.operator_concept_id,
       m.value_as_number,
       m.value_as_concept_id,
       m.unit_concept_id,
       m.range_low,
       m.range_high,
       m.provider_id,
       m.visit_occurrence_id,
       m.visit_detail_id,
       m.measurement_source_value,
       m.measurement_source_concept_id,
       m.unit_source_value,
       m.unit_source_concept_id,
       m.value_source_value,
       m.measurement_event_id,
       m.meas_event_field_concept_id
FROM src_enriched m;
