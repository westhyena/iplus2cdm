-- 빈 청구코드 원내 라인 (참고용 — hira 매핑 대상이 아니라 원내 코드 체계 정비 대상)
-- 대상: 슬립에서 청구코드가 비어 있는 라인의 명칭별 집계
--   (제증명, 물품판매, 시력교정수술, T-렌즈, CRT 드림렌즈 등)
;WITH slip AS (
  SELECT
    'OP' AS src,
    LTRIM(RTRIM(CAST(o.[명칭] AS nvarchar(200)))) AS name_,
    ISNULL(LTRIM(RTRIM(CAST(o.[보험분류] AS varchar(10)))), '') AS ins_class,
    o.[진료일자] AS svc_date,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amt
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND NULLIF(LTRIM(RTRIM(CAST(o.[청구코드] AS varchar(50)))), '') IS NULL
  UNION ALL
  SELECT
    'IP',
    LTRIM(RTRIM(CAST(i.[명칭] AS nvarchar(200)))),
    ISNULL(LTRIM(RTRIM(CAST(i.[보험분류] AS varchar(10)))), ''),
    i.[진료일자],
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),''))
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND NULLIF(LTRIM(RTRIM(CAST(i.[청구코드] AS varchar(50)))), '') IS NULL
)
SELECT
  s.name_          AS 명칭,
  s.src            AS 구분,
  s.ins_class      AS 보험분류,
  COUNT(*)         AS 라인수,
  CAST(SUM(ISNULL(s.amt, 0)) AS bigint) AS 금액합,
  MIN(s.svc_date)  AS 최초사용일,
  MAX(s.svc_date)  AS 최근사용일
FROM slip s
GROUP BY s.name_, s.src, s.ins_class
ORDER BY CAST(SUM(ISNULL(s.amt, 0)) AS bigint) DESC;
