SET NOCOUNT ON;

-- 조건발생 ID 자동증가: 시퀀스와 기본값 보장
BEGIN TRY
  BEGIN TRAN;

  -- 1) 시퀀스 없으면 생성
  IF NOT EXISTS (
    SELECT 1
    FROM sys.sequences sq
    JOIN sys.schemas sc ON sc.schema_id = sq.schema_id
    WHERE sq.name = 'seq_condition_occurrence_id' AND sc.name = '$(CdmSchema)'
  )
  BEGIN
    EXEC('CREATE SEQUENCE [$(CdmSchema)].[seq_condition_occurrence_id] AS INT START WITH 1 INCREMENT BY 1');
  END;

  -- 2) 현재 MAX + 1로 RESTART (기존 데이터 고려)
  DECLARE @max_id INT = ISNULL((SELECT MAX(condition_occurrence_id) FROM [$(CdmSchema)].[condition_occurrence]), 0);
  DECLARE @restart_sql nvarchar(400) = N'ALTER SEQUENCE [$(CdmSchema)].[seq_condition_occurrence_id] RESTART WITH ' + CAST(@max_id + 1 AS nvarchar(20));
  EXEC(@restart_sql);

  -- 3) 컬럼에 기본값(시퀀스) 없으면 추가
  IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.default_object_id = dc.object_id
    JOIN sys.tables t ON t.object_id = c.object_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = '$(CdmSchema)'
      AND t.name = 'condition_occurrence'
      AND c.name = 'condition_occurrence_id'
  )
  BEGIN
    ALTER TABLE [$(CdmSchema)].[condition_occurrence]
      ADD CONSTRAINT DF_condition_occurrence_id_seq
      DEFAULT (NEXT VALUE FOR [$(CdmSchema)].[seq_condition_occurrence_id]) FOR condition_occurrence_id;
  END;

  COMMIT;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK;
  THROW;
END CATCH

-- 공통 CTE
;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), visit_map AS (
  SELECT ptntidno, [date], [source], visit_occurrence_id FROM [$(StagingSchema)].visit_occurrence_map
), cond_map AS (
  -- 사용자 제공 매핑: 원본 코드에서 '.' 제거 후 매핑 우선 적용
  SELECT
    m.source_code,
    m.target_concept_id,
    m.source_concept_id
  FROM [$(StagingSchema)].condition_vocabulary_map m
), op_raw AS (
  SELECT
    o.PTNTIDNO,
    o.[진료일자],
    o.[상병구분],
    o.[상병코드],
    o.row_i AS row_i
  FROM  [$(SrcSchema)].[OCSDISE] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND ISNULL(o.[RO상병],'0') <> '1'
    AND ISNULL(o.[상병구분],'') <> '5'
    AND TRY_CONVERT(date, o.[진료일자]) IS NOT NULL
    AND NULLIF(LTRIM(RTRIM(o.[상병코드])),'') IS NOT NULL
), ip_raw AS (
  SELECT
    i.PTNTIDNO,
    i.[진료일자],
    i.[상병구분],
    i.[상병코드],
    i.row_i AS row_i
  FROM  [$(SrcSchema)].[OCSDISEI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND ISNULL(i.[RO상병],'0') <> '1'
    AND ISNULL(i.[상병구분],'') <> '5'
    AND TRY_CONVERT(date, i.[진료일자]) IS NOT NULL
    AND NULLIF(LTRIM(RTRIM(i.[상병코드])),'') IS NOT NULL
), op_enriched AS (
  SELECT
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.[진료일자]) AS condition_start_date,
    NULL AS condition_start_datetime,
    -- 종료일자: 방문 종료일 사용 (시간 없음)
    NULL AS condition_end_datetime,
    -- 상태: row_i = 0 이면 주상병(32902), 그 외 부상병(32908)
    CASE WHEN TRY_CONVERT(int, r.row_i) = 0 THEN 32902 ELSE 32908 END AS condition_status_concept_id,
    CAST(r.[상병코드] AS varchar(50)) AS condition_source_value,
    REPLACE(CAST(r.[상병코드] AS varchar(200)),'.','') AS normalized_code,
    'OP' AS src
  FROM op_raw r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map  vm ON vm.ptntidno = r.PTNTIDNO AND vm.[date] = REPLACE(r.[진료일자], '-', '') AND vm.[source] = 'OP'
), ip_enriched AS (
  SELECT
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.[진료일자]) AS condition_start_date,
    NULL AS condition_start_datetime,
    NULL AS condition_end_datetime,
    CASE WHEN TRY_CONVERT(int, r.row_i) = 0 THEN 32902 ELSE 32908 END AS condition_status_concept_id,
    CAST(r.[상병코드] AS varchar(50)) AS condition_source_value,
    REPLACE(CAST(r.[상병코드] AS varchar(200)),'.','') AS normalized_code,
    'IP' AS src
  FROM ip_raw r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map  vm ON vm.ptntidno = r.PTNTIDNO AND vm.[date] = REPLACE(r.[진료일자], '-', '') AND vm.[source] = 'IP'
), unioned AS (
  SELECT * FROM op_enriched
  UNION ALL
  SELECT * FROM ip_enriched
), final_enriched AS (
  SELECT
    u.person_id,
    COALESCE(cm.target_concept_id, 0) AS condition_concept_id,
    u.condition_start_date,
    u.condition_start_datetime,
    -- 종료일자는 방문 테이블에서 연결해 가져오기 (없으면 start_date)
    COALESCE(try_convert(date, vo.visit_end_date), u.condition_start_date) AS condition_end_date,
    NULL AS condition_end_datetime,
    32817 AS condition_type_concept_id,
    u.condition_status_concept_id,
    NULL AS stop_reason,
    NULL AS provider_id,
    u.visit_occurrence_id,
    NULL AS visit_detail_id,
    u.condition_source_value,
    cm.source_concept_id AS condition_source_concept_id,
    NULL AS condition_status_source_value
  FROM unioned u
  LEFT JOIN cond_map cm ON cm.source_code = u.normalized_code
  LEFT JOIN [$(CdmSchema)].visit_occurrence vo ON vo.visit_occurrence_id = u.visit_occurrence_id
)

-- 신규만 삽입
INSERT INTO [$(CdmSchema)].[condition_occurrence](
  person_id,
  condition_concept_id,
  condition_start_date,
  condition_start_datetime,
  condition_end_date,
  condition_end_datetime,
  condition_type_concept_id,
  condition_status_concept_id,
  stop_reason,
  provider_id,
  visit_occurrence_id,
  visit_detail_id,
  condition_source_value,
  condition_source_concept_id,
  condition_status_source_value
)
SELECT v.person_id,
       v.condition_concept_id,
       v.condition_start_date,
       v.condition_start_datetime,
       v.condition_end_date,
       v.condition_end_datetime,
       v.condition_type_concept_id,
       v.condition_status_concept_id,
       v.stop_reason,
       v.provider_id,
       v.visit_occurrence_id,
       v.visit_detail_id,
       v.condition_source_value,
       v.condition_source_concept_id,
       v.condition_status_source_value
FROM final_enriched v
;


