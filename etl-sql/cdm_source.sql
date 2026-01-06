INSERT INTO $(CdmSchema).cdm_source (
    cdm_source_name,
    cdm_source_abbreviation,
    cdm_holder,
    source_description,
    source_documentation_reference,
    cdm_etl_reference,
    source_release_date,
    cdm_release_date,
    cdm_version,
    cdm_version_concept_id,
    vocabulary_version
)
SELECT
    '$(CDM_SOURCE_NAME)',
    '$(CDM_SOURCE_ABBREVIATION)',
    '$(CDM_HOLDER)',
    '$(SOURCE_DESCRIPTION)',
    NULLIF('$(SOURCE_DOCUMENTATION_REFERENCE)', ''),
    NULLIF('$(CDM_ETL_REFERENCE)', ''),
    CAST('$(SOURCE_RELEASE_DATE)' AS DATE),
    CURRENT_DATE,
    '$(CDM_VERSION)',
    756265, -- CDM v5.3.1 concept id (commonly used for 5.4 as well, or update if specific one exists)
    '$(VOCABULARY_VERSION)'
WHERE NOT EXISTS (SELECT 1 FROM $(CdmSchema).cdm_source);
