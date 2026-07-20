-- 미매핑 시술/검사 코드 (의료진 매핑 요청용)
-- 대상: 외래+입원 슬립에서 실제 사용된 청구코드 중
--   약(수가분류 3)·재료(수가분류 8) 제외, 빈 코드 제외,
--   hira_map에 유효 매핑(INVALID_REASON 없음 + concept 존재)이 전혀 없는 코드
;WITH slip AS (
  SELECT
    UPPER(LTRIM(RTRIM(CAST(o.[청구코드] AS varchar(50))))) AS code_,
    LTRIM(RTRIM(CAST(o.[명칭] AS nvarchar(200)))) AS name_,
    o.[진료일자] AS svc_date,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amt,
    LTRIM(RTRIM(CAST(o.[수가분류] AS varchar(10)))) AS line_class
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
  UNION ALL
  SELECT
    UPPER(LTRIM(RTRIM(CAST(i.[청구코드] AS varchar(50))))),
    LTRIM(RTRIM(CAST(i.[명칭] AS nvarchar(200)))),
    i.[진료일자],
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),'')),
    LTRIM(RTRIM(CAST(i.[수가분류] AS varchar(10))))
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
), used AS (
  SELECT code_,
         MAX(name_) AS slip_name,
         COUNT(*) AS line_cnt,
         CAST(SUM(ISNULL(amt, 0)) AS bigint) AS amt_sum,
         MIN(svc_date) AS first_used,
         MAX(svc_date) AS last_used
  FROM slip
  WHERE NULLIF(code_, '') IS NOT NULL
    AND ISNULL(line_class, '') <> '3'
  GROUP BY code_
), meta AS (
  SELECT
    UPPER(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(50))))) AS code_,
    MAX(LTRIM(RTRIM(CAST(p.[한글명] AS nvarchar(200))))) AS kr_name,
    MAX(LTRIM(RTRIM(CAST(p.[보험분류] AS varchar(10))))) AS ins_class,
    MAX(LTRIM(RTRIM(CAST(p.[수익분류] AS varchar(10))))) AS rev_class,
    MAX(LTRIM(RTRIM(CAST(p.[수가분류] AS varchar(10))))) AS fee_class
  FROM [$(SrcSchema)].[PICMECHM] p
  GROUP BY UPPER(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(50)))))
)
SELECT
  u.code_        AS 청구코드,
  u.slip_name    AS 슬립명칭,
  m.kr_name      AS 마스터한글명,
  m.ins_class    AS 보험분류,
  m.fee_class    AS 수가분류,
  u.line_cnt     AS 사용라인수,
  u.amt_sum      AS 금액합,
  u.first_used   AS 최초사용일,
  u.last_used    AS 최근사용일
FROM used u
LEFT JOIN meta m ON m.code_ = u.code_
WHERE ISNULL(m.fee_class, '') NOT IN ('3', '8')
  AND NOT EXISTS (
    SELECT 1 FROM [$(StagingSchema)].hira_map h
    WHERE UPPER(LTRIM(RTRIM(CAST(h.LOCAL_CD1 AS varchar(50))))) = u.code_ COLLATE DATABASE_DEFAULT
      AND h.INVALID_REASON IS NULL
      AND TRY_CONVERT(int, h.TARGET_CONCEPT_ID_1) IS NOT NULL
  )
ORDER BY u.amt_sum DESC;
