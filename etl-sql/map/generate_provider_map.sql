SET NOCOUNT ON;

-- 신규 의사 ID 매핑 추가
-- 임상 이벤트가 참조하는 사용자 계정(진료의/담당의/주치의)을 모두 수집한다.
-- PICUSERM(사용자정보)에 없는 계정도 이벤트에 등장하면 provider로 등록한다.
INSERT INTO [$(StagingSchema)].provider_id_map (userid, provider_id)
SELECT s.userid,
       x.base_id + ROW_NUMBER() OVER (ORDER BY s.userid)
FROM (
  SELECT NULLIF(LTRIM(RTRIM([담당의])), '') AS userid FROM [$(SrcSchema)].[OCSSLIP]
  UNION
  SELECT NULLIF(LTRIM(RTRIM([담당의])), '') FROM [$(SrcSchema)].[OCSSLIPI]
  UNION
  SELECT NULLIF(LTRIM(RTRIM([담당의])), '') FROM [$(SrcSchema)].[OCSDISE]
  UNION
  SELECT NULLIF(LTRIM(RTRIM([담당의])), '') FROM [$(SrcSchema)].[OCSDISEI]
  UNION
  SELECT NULLIF(LTRIM(RTRIM(OTPTDOCT)), '') FROM [$(SrcSchema)].[PMOOTPTH]
  UNION
  SELECT NULLIF(LTRIM(RTRIM(IPHSDOCT)), '') FROM [$(SrcSchema)].[PMIIPHSH]
  UNION
  SELECT NULLIF(LTRIM(RTRIM(PTNTDOCT)), '') FROM [$(SrcSchema)].[PMCPTNT]
) s
CROSS JOIN (
  SELECT ISNULL(MAX(provider_id),0) AS base_id FROM [$(StagingSchema)].provider_id_map
) x
LEFT JOIN [$(StagingSchema)].provider_id_map m
  ON m.userid = s.userid
WHERE s.userid IS NOT NULL
  AND m.userid IS NULL;
