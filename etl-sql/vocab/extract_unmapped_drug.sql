-- 미매핑 약 코드 (drug concept 매핑 요청용)
-- 대상: 슬립에서 수가분류 3(약)으로 사용된 청구코드 중
--   hira_map(Drug)에 유효 매핑이 없는 코드 (의료진 별도 매핑은 미사용)
;WITH slip AS (
  SELECT
    UPPER(LTRIM(RTRIM(CAST(o.[청구코드] AS varchar(50))))) AS code_,
    LTRIM(RTRIM(CAST(o.[명칭] AS nvarchar(200)))) AS name_,
    o.[진료일자] AS svc_date,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amt
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND LTRIM(RTRIM(CAST(o.[수가분류] AS varchar(10)))) = '3'
  UNION ALL
  SELECT
    UPPER(LTRIM(RTRIM(CAST(i.[청구코드] AS varchar(50))))),
    LTRIM(RTRIM(CAST(i.[명칭] AS nvarchar(200)))),
    i.[진료일자],
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),''))
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND LTRIM(RTRIM(CAST(i.[수가분류] AS varchar(10)))) = '3'
), used AS (
  SELECT code_,
         MAX(name_) AS slip_name,
         COUNT(*) AS line_cnt,
         CAST(SUM(ISNULL(amt, 0)) AS bigint) AS amt_sum,
         MAX(svc_date) AS last_used
  FROM slip
  WHERE NULLIF(code_, '') IS NOT NULL
  GROUP BY code_
), meta AS (
  SELECT
    UPPER(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(50))))) AS code_,
    MAX(LTRIM(RTRIM(CAST(p.[한글명] AS nvarchar(200))))) AS kr_name,
    MAX(LTRIM(RTRIM(CAST(p.[성분코드] AS varchar(20))))) AS ingredient_code,
    MAX(LTRIM(RTRIM(CAST(p.[제약회사명] AS nvarchar(100))))) AS maker_
  FROM [$(SrcSchema)].[PICMECHM] p
  GROUP BY UPPER(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(50)))))
)
SELECT
  u.code_            AS 청구코드,
  u.slip_name        AS 슬립명칭,
  m.kr_name          AS 마스터한글명,
  m.ingredient_code  AS 성분코드,
  m.maker_           AS 제조사,
  u.line_cnt         AS 사용라인수,
  u.amt_sum          AS 금액합,
  u.last_used        AS 최근사용일
FROM used u
LEFT JOIN meta m ON m.code_ = u.code_
WHERE NOT EXISTS (
    SELECT 1 FROM [$(StagingSchema)].hira_map h
    WHERE UPPER(LTRIM(RTRIM(CAST(h.LOCAL_CD1 AS varchar(50))))) = u.code_ COLLATE DATABASE_DEFAULT
      AND h.TARGET_DOMAIN_ID = 'Drug'
      AND h.INVALID_REASON IS NULL
      AND TRY_CONVERT(int, h.TARGET_CONCEPT_ID_1) IS NOT NULL
  )
ORDER BY u.amt_sum DESC;
