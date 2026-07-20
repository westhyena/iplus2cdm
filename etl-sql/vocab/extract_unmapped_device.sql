-- 미매핑 재료 코드 (렌즈 등 — device concept 매핑 요청용)
-- 대상: PICMECHM 수가분류 8(재료) 코드 중 슬립에서 사용되었고
--   hira_map(Device)에 유효 매핑이 없는 코드
;WITH slip AS (
  SELECT
    UPPER(LTRIM(RTRIM(CAST(o.[청구코드] AS varchar(50))))) AS code_,
    LTRIM(RTRIM(CAST(o.[명칭] AS nvarchar(200)))) AS name_,
    o.[진료일자] AS svc_date,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amt
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
  UNION ALL
  SELECT
    UPPER(LTRIM(RTRIM(CAST(i.[청구코드] AS varchar(50))))),
    LTRIM(RTRIM(CAST(i.[명칭] AS nvarchar(200)))),
    i.[진료일자],
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),''))
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
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
    MAX(LTRIM(RTRIM(CAST(p.[영문명] AS nvarchar(200))))) AS en_name,
    MAX(LTRIM(RTRIM(CAST(p.[규격] AS nvarchar(100))))) AS spec_,
    MAX(LTRIM(RTRIM(CAST(p.[제약회사명] AS nvarchar(100))))) AS maker_,
    MAX(LTRIM(RTRIM(CAST(p.[보험분류] AS varchar(10))))) AS ins_class
  FROM [$(SrcSchema)].[PICMECHM] p
  WHERE TRY_CONVERT(int, p.[수가분류]) = 8
    AND NULLIF(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(50)))), '') IS NOT NULL
  GROUP BY UPPER(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(50)))))
)
SELECT
  m.code_      AS 청구코드,
  u.slip_name  AS 슬립명칭,
  m.kr_name    AS 마스터한글명,
  m.en_name    AS 영문명,
  m.spec_      AS 규격,
  m.maker_     AS 제조사,
  m.ins_class  AS 보험분류,
  u.line_cnt   AS 사용라인수,
  u.amt_sum    AS 금액합,
  u.last_used  AS 최근사용일
FROM meta m
JOIN used u ON u.code_ = m.code_
WHERE NOT EXISTS (
    SELECT 1 FROM [$(StagingSchema)].hira_map h
    WHERE UPPER(LTRIM(RTRIM(CAST(h.LOCAL_CD1 AS varchar(50))))) = m.code_ COLLATE DATABASE_DEFAULT
      AND h.TARGET_DOMAIN_ID = 'Device'
      AND h.INVALID_REASON IS NULL
      AND TRY_CONVERT(int, h.TARGET_CONCEPT_ID_1) IS NOT NULL
  )
ORDER BY u.amt_sum DESC;
