-- 미매핑 상병 코드 (condition concept 매핑 요청용)
-- 대상: 진단 테이블(OCSDISE/OCSDISEI)에서 사용된 상병코드 중
--   hira_map(Condition)에 유효 매핑이 없는 코드 (의료진 별도 매핑은 미사용)
;WITH dise AS (
  SELECT
    UPPER(LTRIM(RTRIM(CAST(o.[상병코드] AS varchar(50))))) AS code_,
    LTRIM(RTRIM(CAST(o.[명칭] AS nvarchar(200)))) AS name_,
    o.[진료일자] AS svc_date
  FROM [$(SrcSchema)].[OCSDISE] o
  WHERE o.PTNTIDNO IS NOT NULL
  UNION ALL
  SELECT
    UPPER(LTRIM(RTRIM(CAST(i.[상병코드] AS varchar(50))))),
    LTRIM(RTRIM(CAST(i.[명칭] AS nvarchar(200)))),
    i.[진료일자]
  FROM [$(SrcSchema)].[OCSDISEI] i
  WHERE i.PTNTIDNO IS NOT NULL
)
SELECT
  d.code_          AS 상병코드,
  MAX(d.name_)     AS 명칭,
  COUNT(*)         AS 사용건수,
  MIN(d.svc_date)  AS 최초사용일,
  MAX(d.svc_date)  AS 최근사용일
FROM dise d
WHERE NULLIF(d.code_, '') IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM [$(StagingSchema)].hira_map h
    WHERE UPPER(LTRIM(RTRIM(CAST(h.LOCAL_CD1 AS varchar(50))))) = d.code_ COLLATE DATABASE_DEFAULT
      AND h.TARGET_DOMAIN_ID = 'Condition'
      AND h.INVALID_REASON IS NULL
      AND TRY_CONVERT(int, h.TARGET_CONCEPT_ID_1) IS NOT NULL
  )
GROUP BY d.code_
ORDER BY COUNT(*) DESC;
