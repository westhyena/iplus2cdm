-- 미매핑 검안 항목 (measurement concept 매핑 요청용)
-- 대상: 검사장비 마스터(INFLABM)의 항목 중 measurement_vocabulary_map에
--   유효 concept(공통/우안/좌안 중 하나라도)이 없는 항목 + 실제 기록 건수(INFLABD)
;WITH items AS (
  SELECT
    m.LABID,
    LTRIM(RTRIM(CAST(m.LABNM AS nvarchar(100)))) AS LABNM,
    v.ItemNumber,
    LTRIM(RTRIM(CAST(v.ItemName AS nvarchar(100)))) AS ItemName,
    LTRIM(RTRIM(CAST(v.Symbol AS nvarchar(50)))) AS Symbol
  FROM [$(SrcSchema)].[INFLABM] m
  CROSS APPLY (
    VALUES
      ('Item1', m.Item1, m.Symbol1), ('Item2', m.Item2, m.Symbol2), ('Item3', m.Item3, m.Symbol3), ('Item4', m.Item4, m.Symbol4), ('Item5', m.Item5, m.Symbol5),
      ('Item6', m.Item6, m.Symbol6), ('Item7', m.Item7, m.Symbol7), ('Item8', m.Item8, m.Symbol8), ('Item9', m.Item9, m.Symbol9), ('Item10', m.Item10, m.Symbol10),
      ('Item11', m.Item11, m.Symbol11), ('Item12', m.Item12, m.Symbol12), ('Item13', m.Item13, m.Symbol13), ('Item14', m.Item14, m.Symbol14), ('Item15', m.Item15, m.Symbol15),
      ('Item16', m.Item16, m.Symbol16), ('Item17', m.Item17, m.Symbol17), ('Item18', m.Item18, m.Symbol18), ('Item19', m.Item19, m.Symbol19), ('Item20', m.Item20, m.Symbol20),
      ('Item21', m.Item21, m.Symbol21), ('Item22', m.Item22, m.Symbol22), ('Item23', m.Item23, m.Symbol23), ('Item24', m.Item24, m.Symbol24), ('Item25', m.Item25, m.Symbol25),
      ('Item26', m.Item26, m.Symbol26), ('Item27', m.Item27, m.Symbol27), ('Item28', m.Item28, m.Symbol28), ('Item29', m.Item29, m.Symbol29), ('Item30', m.Item30, m.Symbol30),
      ('Item31', m.Item31, m.Symbol31), ('Item32', m.Item32, m.Symbol32), ('Item33', m.Item33, m.Symbol33), ('Item34', m.Item34, m.Symbol34), ('Item35', m.Item35, m.Symbol35),
      ('Item36', m.Item36, m.Symbol36), ('Item37', m.Item37, m.Symbol37), ('Item38', m.Item38, m.Symbol38), ('Item39', m.Item39, m.Symbol39), ('Item40', m.Item40, m.Symbol40)
  ) AS v(ItemNumber, ItemName, Symbol)
  WHERE NULLIF(LTRIM(RTRIM(CAST(v.ItemName AS nvarchar(100)))), '') IS NOT NULL
), usage_ AS (
  SELECT d.LABID, v.ItemNumber, COUNT(*) AS value_cnt, MAX(d.REGDATE) AS last_used
  FROM [$(SrcSchema)].[INFLABD] d
  CROSS APPLY (
    VALUES
      ('Item1', d.Item1), ('Item2', d.Item2), ('Item3', d.Item3), ('Item4', d.Item4), ('Item5', d.Item5),
      ('Item6', d.Item6), ('Item7', d.Item7), ('Item8', d.Item8), ('Item9', d.Item9), ('Item10', d.Item10),
      ('Item11', d.Item11), ('Item12', d.Item12), ('Item13', d.Item13), ('Item14', d.Item14), ('Item15', d.Item15),
      ('Item16', d.Item16), ('Item17', d.Item17), ('Item18', d.Item18), ('Item19', d.Item19), ('Item20', d.Item20),
      ('Item21', d.Item21), ('Item22', d.Item22), ('Item23', d.Item23), ('Item24', d.Item24), ('Item25', d.Item25),
      ('Item26', d.Item26), ('Item27', d.Item27), ('Item28', d.Item28), ('Item29', d.Item29), ('Item30', d.Item30),
      ('Item31', d.Item31), ('Item32', d.Item32), ('Item33', d.Item33), ('Item34', d.Item34), ('Item35', d.Item35),
      ('Item36', d.Item36), ('Item37', d.Item37), ('Item38', d.Item38), ('Item39', d.Item39), ('Item40', d.Item40)
  ) AS v(ItemNumber, ItemValue)
  WHERE NULLIF(LTRIM(RTRIM(CAST(v.ItemValue AS nvarchar(100)))), '') IS NOT NULL
  GROUP BY d.LABID, v.ItemNumber
)
SELECT
  i.LABID              AS 장비ID,
  i.LABNM              AS 검사명,
  i.ItemNumber         AS 항목번호,
  i.ItemName           AS 항목명,
  i.Symbol             AS 단위기호,
  ISNULL(u.value_cnt, 0) AS 기록건수,
  u.last_used          AS 최근기록일
FROM items i
LEFT JOIN usage_ u ON u.LABID = i.LABID AND u.ItemNumber = i.ItemNumber
WHERE NOT EXISTS (
    SELECT 1 FROM [$(StagingSchema)].measurement_vocabulary_map mv
    WHERE UPPER(LTRIM(RTRIM(mv.LABNM))) = UPPER(i.LABNM) COLLATE DATABASE_DEFAULT
      AND UPPER(LTRIM(RTRIM(mv.ItemName))) = UPPER(i.ItemName) COLLATE DATABASE_DEFAULT
      AND (mv.common_concept_id IS NOT NULL OR mv.right_concept_id IS NOT NULL OR mv.left_concept_id IS NOT NULL)
  )
ORDER BY ISNULL(u.value_cnt, 0) DESC;
