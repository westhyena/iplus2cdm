SET NOCOUNT ON;

-- default param
DECLARE @MinId INT = $(MinId);

;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), visit_map AS (
  SELECT ptntidno, [date], [source], visit_occurrence_id FROM [$(StagingSchema)].visit_occurrence_map
), raw_data AS (
  SELECT 
    PTNTIDNO,
    [진료일자] AS note_date,
    'OP' AS source_type,
    [내용] AS note_text
  FROM [$(SrcSchema)].[OCSPRES]
  WHERE PTNTIDNO IS NOT NULL
  
  UNION ALL
  
  SELECT 
    PTNTIDNO,
    [진료일자] AS note_date,
    'IP' AS source_type,
    [내용] AS note_text
  FROM [$(SrcSchema)].[OCSPRESI]
  WHERE PTNTIDNO IS NOT NULL
), enriched AS (
  SELECT
    r.PTNTIDNO AS k_ptntidno,
    REPLACE(r.note_date, '-', '') AS k_date,
    r.source_type AS k_source,
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.note_date) AS note_date,
    -- Combine date and time if time available, otherwise just date as datetime? 
    -- User didn't specify time col, so use date cast to datetime (00:00:00)
    NULL AS note_datetime,
    32817 AS note_type_concept_id, -- User spec
    706391 AS note_class_concept_id, -- User spec
    '' AS note_title, -- User spec
    r.note_text,
    32678 AS encoding_concept_id, -- UTF-8 (Standard)
    4175771 AS language_concept_id, -- User spec
    NULL AS note_source_value
  FROM raw_data r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map vm ON vm.ptntidno = r.PTNTIDNO 
                        AND vm.[date] = REPLACE(r.note_date, '-', '') 
                        AND vm.[source] = r.source_type
)
SELECT
  ROW_NUMBER() OVER (ORDER BY k_ptntidno, k_date, k_source, note_source_value) + @MinId AS note_id,
  person_id,
  note_date,
  note_datetime,
  note_type_concept_id,
  note_class_concept_id,
  note_title,
  note_text,
  encoding_concept_id,
  language_concept_id,
  NULL AS provider_id,
  visit_occurrence_id,
  NULL AS visit_detail_id,
  note_source_value,
  NULL AS note_event_id,
  NULL AS note_event_field_concept_id
FROM enriched
WHERE note_text IS NOT NULL AND LEN(note_text) > 0;
