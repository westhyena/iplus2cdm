SET NOCOUNT ON;

-- default param
DECLARE @MinId INT = $(MinId);

;WITH provider_map AS (
  SELECT userid, provider_id
  FROM [$(StagingSchema)].provider_id_map
  WHERE provider_id > $(MinId)  -- Optimization: Incremental Extract
), user_master AS (
  -- PICUSERM(사용자정보): userid 기준 최신 1행만 사용
  SELECT
    LTRIM(RTRIM(u.USERID)) AS userid,
    NULLIF(LTRIM(RTRIM(u.USERNAME)), '') AS user_name,
    NULLIF(LTRIM(RTRIM(u.USERDEPT)), '') AS user_dept,
    NULLIF(TRY_CONVERT(int, SUBSTRING(LTRIM(RTRIM(u.USERBIDT)), 1, 4)), 0) AS birth_year,
    ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(u.USERID)) ORDER BY u.MODIFYDATE DESC) AS rn
  FROM [$(SrcSchema)].[PICUSERM] u
  WHERE NULLIF(LTRIM(RTRIM(u.USERID)), '') IS NOT NULL
)
SELECT
  m.provider_id,
  COALESCE(u.user_name, m.userid) AS provider_name,
  NULL AS npi,
  NULL AS dea,
  0 AS specialty_concept_id,
  NULL AS care_site_id,
  u.birth_year AS year_of_birth,
  0 AS gender_concept_id,
  m.userid AS provider_source_value,
  u.user_dept AS specialty_source_value,
  NULL AS specialty_source_concept_id,
  NULL AS gender_source_value,
  NULL AS gender_source_concept_id
FROM provider_map m
LEFT JOIN user_master u
  ON u.userid = m.userid AND u.rn = 1;
