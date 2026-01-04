SET NOCOUNT ON;

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
    NULLIF(TRY_CONVERT(int, SUBSTRING(r.PTNTBITH,1,4)), 0) AS year_of_birth,
    NULLIF(TRY_CONVERT(int, SUBSTRING(r.PTNTBITH,5,2)), 0) AS month_of_birth,
    NULLIF(TRY_CONVERT(int, SUBSTRING(r.PTNTBITH,7,2)), 0) AS day_of_birth,
    TRY_CONVERT(datetime, STUFF(STUFF(r.PTNTBITH,5,0,'-'),8,0,'-') + ' 00:00:00') AS birth_datetime,
    NULLIF(LTRIM(RTRIM(r.PTNTIDNO)), '') AS person_source_value,
    NULLIF(LTRIM(RTRIM(r.PTNTSEXX)), '') AS gender_source_value
  FROM src_raw r
  JOIN map m ON m.ptntidno = r.PTNTIDNO
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
FROM src_enriched v
WHERE v.year_of_birth IS NOT NULL;
