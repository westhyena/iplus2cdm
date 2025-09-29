SET NOCOUNT ON;

-- 신규 소스 ID 매핑 추가
INSERT INTO  [$(StagingSchema)].person_id_map (ptntidno, person_id)
SELECT s.PTNTIDNO,
       x.base_id + ROW_NUMBER() OVER (ORDER BY s.PTNTIDNO)
FROM (
  SELECT DISTINCT PTNTIDNO
  FROM  [$(SrcSchema)].[PMCPTNT]
  WHERE PTNTIDNO IS NOT NULL
) s
CROSS JOIN (
  SELECT ISNULL(MAX(person_id),0) AS base_id FROM [$(StagingSchema)].person_id_map
) x
LEFT JOIN [$(StagingSchema)].person_id_map m
  ON m.ptntidno = s.PTNTIDNO
WHERE m.ptntidno IS NULL;

-- 실제 소스/매핑 사용 CTE
;WITH src_raw AS (
  SELECT DISTINCT
         p.PTNTIDNO,
         p.PTNTSEXX,
         p.PTNTBITH
  FROM  [$(SrcSchema)].[PMCPTNT] p
  WHERE p.PTNTIDNO IS NOT NULL
), map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), src_enriched AS (
  SELECT
    m.person_id,
    -- 성별 매핑: 남=8507, 여=8532, 그 외=8551(Unknown)
    CASE
      WHEN UPPER(LTRIM(RTRIM(r.PTNTSEXX))) IN ('M','MALE','남','남자','1') THEN 8507
      WHEN UPPER(LTRIM(RTRIM(r.PTNTSEXX))) IN ('F','FEMALE','여','여자','2') THEN 8532
      ELSE 8551
    END AS gender_concept_id,
    TRY_CONVERT(int, SUBSTRING(r.PTNTBITH,1,4)) AS year_of_birth,
    TRY_CONVERT(int, SUBSTRING(r.PTNTBITH,5,2)) AS month_of_birth,
    TRY_CONVERT(int, SUBSTRING(r.PTNTBITH,7,2)) AS day_of_birth,
    TRY_CONVERT(datetime, STUFF(STUFF(r.PTNTBITH,5,0,'-'),8,0,'-') + ' 00:00:00') AS birth_datetime,
    r.PTNTIDNO AS person_source_value,
    r.PTNTSEXX AS gender_source_value
  FROM src_raw r
  JOIN map m ON m.ptntidno = r.PTNTIDNO
), valid AS (
  SELECT *
  FROM src_enriched v
  WHERE v.year_of_birth BETWEEN 1850 AND YEAR(GETDATE())
    AND v.month_of_birth BETWEEN 1 AND 12
    AND v.day_of_birth BETWEEN 1 AND 31
)

-- 업데이트(기존 존재 시)
UPDATE tgt
SET   tgt.gender_concept_id = v.gender_concept_id,
      tgt.year_of_birth     = v.year_of_birth,
      tgt.month_of_birth    = v.month_of_birth,
      tgt.day_of_birth      = v.day_of_birth,
      tgt.birth_datetime    = v.birth_datetime,
      tgt.person_source_value = v.person_source_value,
      tgt.gender_source_value = v.gender_source_value
FROM  [$(CdmSchema)].[person] AS tgt
JOIN  valid v
  ON  v.person_id = tgt.person_id;

-- 삽입(신규만)
;WITH src_raw AS (
  SELECT DISTINCT
         p.PTNTIDNO,
         p.PTNTSEXX,
         p.PTNTBITH
  FROM  [$(SrcSchema)].[PMCPTNT] p
  WHERE p.PTNTIDNO IS NOT NULL
), map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), src_enriched AS (
  SELECT
    m.person_id,
    CASE
      WHEN UPPER(LTRIM(RTRIM(r.PTNTSEXX))) IN ('M','MALE','남','남자','1') THEN 8507
      WHEN UPPER(LTRIM(RTRIM(r.PTNTSEXX))) IN ('F','FEMALE','여','여자','2') THEN 8532
      ELSE 8551
    END AS gender_concept_id,
    TRY_CONVERT(int, SUBSTRING(r.PTNTBITH,1,4)) AS year_of_birth,
    TRY_CONVERT(int, SUBSTRING(r.PTNTBITH,5,2)) AS month_of_birth,
    TRY_CONVERT(int, SUBSTRING(r.PTNTBITH,7,2)) AS day_of_birth,
    TRY_CONVERT(datetime, STUFF(STUFF(r.PTNTBITH,5,0,'-'),8,0,'-') + ' 00:00:00') AS birth_datetime,
    r.PTNTIDNO AS person_source_value,
    r.PTNTSEXX AS gender_source_value
  FROM src_raw r
  JOIN map m ON m.ptntidno = r.PTNTIDNO
), valid AS (
  SELECT *
  FROM src_enriched v
  WHERE v.year_of_birth BETWEEN 1850 AND YEAR(GETDATE())
    AND v.month_of_birth BETWEEN 1 AND 12
    AND v.day_of_birth BETWEEN 1 AND 31
)
INSERT INTO [$(CdmSchema)].[person](
  person_id,
  gender_concept_id,
  year_of_birth,
  month_of_birth,
  day_of_birth,
  birth_datetime,
  race_concept_id,
  ethnicity_concept_id,
  location_id,
  provider_id,
  care_site_id,
  person_source_value,
  gender_source_value,
  gender_source_concept_id,
  race_source_value,
  race_source_concept_id,
  ethnicity_source_value,
  ethnicity_source_concept_id
)
SELECT v.person_id,
       v.gender_concept_id,
       v.year_of_birth,
       v.month_of_birth,
       v.day_of_birth,
       v.birth_datetime,
       0 AS race_concept_id,
       0 AS ethnicity_concept_id,
       NULL AS location_id,
       NULL AS provider_id,
       NULL AS care_site_id,
       v.person_source_value,
       v.gender_source_value,
       NULL AS gender_source_concept_id,
       NULL AS race_source_value,
       NULL AS race_source_concept_id,
       NULL AS ethnicity_source_value,
       NULL AS ethnicity_source_concept_id
FROM valid v
WHERE NOT EXISTS (
  SELECT 1 FROM [$(CdmSchema)].[person] p WHERE p.person_id = v.person_id
);


