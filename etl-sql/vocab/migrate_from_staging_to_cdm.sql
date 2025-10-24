ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT] NOCHECK CONSTRAINT fpk_concept_domain_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT] NOCHECK CONSTRAINT fpk_concept_vocabulary_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT] NOCHECK CONSTRAINT fpk_concept_concept_class_id;
ALTER TABLE [$(CDM_SCHEMA)].[VOCABULARY] NOCHECK CONSTRAINT fpk_vocabulary_vocabulary_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DOMAIN] NOCHECK CONSTRAINT fpk_domain_domain_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT_CLASS] NOCHECK CONSTRAINT fpk_concept_class_concept_class_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT_RELATIONSHIP] NOCHECK CONSTRAINT fpk_concept_relationship_concept_id_1;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT_RELATIONSHIP] NOCHECK CONSTRAINT fpk_concept_relationship_concept_id_2;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT_RELATIONSHIP] NOCHECK CONSTRAINT fpk_concept_relationship_relationship_id;
ALTER TABLE [$(CDM_SCHEMA)].[RELATIONSHIP] NOCHECK CONSTRAINT fpk_relationship_relationship_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT_SYNONYM] NOCHECK CONSTRAINT fpk_concept_synonym_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT_SYNONYM] NOCHECK CONSTRAINT fpk_concept_synonym_language_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_STRENGTH] NOCHECK CONSTRAINT fpk_drug_strength_drug_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_STRENGTH] NOCHECK CONSTRAINT fpk_drug_strength_ingredient_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_STRENGTH] NOCHECK CONSTRAINT fpk_drug_strength_amount_unit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_STRENGTH] NOCHECK CONSTRAINT fpk_drug_strength_numerator_unit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_STRENGTH] NOCHECK CONSTRAINT fpk_drug_strength_denominator_unit_concept_id;

-- CDM 데이터 테이블 → Vocabulary (CONCEPT/VOCABULARY/DOMAIN/RELATIONSHIP/CONCEPT_CLASS) 참조 FKs 비활성화
ALTER TABLE [$(CDM_SCHEMA)].[PERSON] NOCHECK CONSTRAINT fpk_person_gender_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PERSON] NOCHECK CONSTRAINT fpk_person_race_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PERSON] NOCHECK CONSTRAINT fpk_person_ethnicity_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PERSON] NOCHECK CONSTRAINT fpk_person_gender_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PERSON] NOCHECK CONSTRAINT fpk_person_race_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PERSON] NOCHECK CONSTRAINT fpk_person_ethnicity_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION_PERIOD] NOCHECK CONSTRAINT fpk_observation_period_period_type_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[VISIT_OCCURRENCE] NOCHECK CONSTRAINT fpk_visit_occurrence_visit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_OCCURRENCE] NOCHECK CONSTRAINT fpk_visit_occurrence_visit_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_OCCURRENCE] NOCHECK CONSTRAINT fpk_visit_occurrence_visit_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_OCCURRENCE] NOCHECK CONSTRAINT fpk_visit_occurrence_admitted_from_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_OCCURRENCE] NOCHECK CONSTRAINT fpk_visit_occurrence_discharged_to_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[VISIT_DETAIL] NOCHECK CONSTRAINT fpk_visit_detail_visit_detail_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_DETAIL] NOCHECK CONSTRAINT fpk_visit_detail_visit_detail_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_DETAIL] NOCHECK CONSTRAINT fpk_visit_detail_visit_detail_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_DETAIL] NOCHECK CONSTRAINT fpk_visit_detail_admitted_from_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_DETAIL] NOCHECK CONSTRAINT fpk_visit_detail_discharged_to_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[CONDITION_OCCURRENCE] NOCHECK CONSTRAINT fpk_condition_occurrence_condition_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONDITION_OCCURRENCE] NOCHECK CONSTRAINT fpk_condition_occurrence_condition_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONDITION_OCCURRENCE] NOCHECK CONSTRAINT fpk_condition_occurrence_condition_status_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONDITION_OCCURRENCE] NOCHECK CONSTRAINT fpk_condition_occurrence_condition_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[DRUG_EXPOSURE] NOCHECK CONSTRAINT fpk_drug_exposure_drug_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_EXPOSURE] NOCHECK CONSTRAINT fpk_drug_exposure_drug_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_EXPOSURE] NOCHECK CONSTRAINT fpk_drug_exposure_route_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_EXPOSURE] NOCHECK CONSTRAINT fpk_drug_exposure_drug_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[PROCEDURE_OCCURRENCE] NOCHECK CONSTRAINT fpk_procedure_occurrence_procedure_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PROCEDURE_OCCURRENCE] NOCHECK CONSTRAINT fpk_procedure_occurrence_procedure_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PROCEDURE_OCCURRENCE] NOCHECK CONSTRAINT fpk_procedure_occurrence_modifier_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PROCEDURE_OCCURRENCE] NOCHECK CONSTRAINT fpk_procedure_occurrence_procedure_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[DEVICE_EXPOSURE] NOCHECK CONSTRAINT fpk_device_exposure_device_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DEVICE_EXPOSURE] NOCHECK CONSTRAINT fpk_device_exposure_device_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DEVICE_EXPOSURE] NOCHECK CONSTRAINT fpk_device_exposure_device_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DEVICE_EXPOSURE] NOCHECK CONSTRAINT fpk_device_exposure_unit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DEVICE_EXPOSURE] NOCHECK CONSTRAINT fpk_device_exposure_unit_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] NOCHECK CONSTRAINT fpk_measurement_measurement_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] NOCHECK CONSTRAINT fpk_measurement_measurement_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] NOCHECK CONSTRAINT fpk_measurement_operator_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] NOCHECK CONSTRAINT fpk_measurement_value_as_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] NOCHECK CONSTRAINT fpk_measurement_unit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] NOCHECK CONSTRAINT fpk_measurement_measurement_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] NOCHECK CONSTRAINT fpk_measurement_unit_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] NOCHECK CONSTRAINT fpk_measurement_meas_event_field_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] NOCHECK CONSTRAINT fpk_observation_observation_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] NOCHECK CONSTRAINT fpk_observation_observation_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] NOCHECK CONSTRAINT fpk_observation_value_as_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] NOCHECK CONSTRAINT fpk_observation_qualifier_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] NOCHECK CONSTRAINT fpk_observation_unit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] NOCHECK CONSTRAINT fpk_observation_observation_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] NOCHECK CONSTRAINT fpk_observation_obs_event_field_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[DEATH] NOCHECK CONSTRAINT fpk_death_death_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DEATH] NOCHECK CONSTRAINT fpk_death_cause_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DEATH] NOCHECK CONSTRAINT fpk_death_cause_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[NOTE] NOCHECK CONSTRAINT fpk_note_note_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[NOTE] NOCHECK CONSTRAINT fpk_note_note_class_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[NOTE] NOCHECK CONSTRAINT fpk_note_encoding_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[NOTE] NOCHECK CONSTRAINT fpk_note_language_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[NOTE] NOCHECK CONSTRAINT fpk_note_note_event_field_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[NOTE_NLP] NOCHECK CONSTRAINT fpk_note_nlp_section_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[NOTE_NLP] NOCHECK CONSTRAINT fpk_note_nlp_note_nlp_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[NOTE_NLP] NOCHECK CONSTRAINT fpk_note_nlp_note_nlp_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[SPECIMEN] NOCHECK CONSTRAINT fpk_specimen_specimen_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[SPECIMEN] NOCHECK CONSTRAINT fpk_specimen_specimen_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[SPECIMEN] NOCHECK CONSTRAINT fpk_specimen_unit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[SPECIMEN] NOCHECK CONSTRAINT fpk_specimen_anatomic_site_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[SPECIMEN] NOCHECK CONSTRAINT fpk_specimen_disease_status_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[FACT_RELATIONSHIP] NOCHECK CONSTRAINT fpk_fact_relationship_domain_concept_id_1;
ALTER TABLE [$(CDM_SCHEMA)].[FACT_RELATIONSHIP] NOCHECK CONSTRAINT fpk_fact_relationship_domain_concept_id_2;
ALTER TABLE [$(CDM_SCHEMA)].[FACT_RELATIONSHIP] NOCHECK CONSTRAINT fpk_fact_relationship_relationship_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[LOCATION] NOCHECK CONSTRAINT fpk_location_country_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[CARE_SITE] NOCHECK CONSTRAINT fpk_care_site_place_of_service_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[PROVIDER] NOCHECK CONSTRAINT fpk_provider_specialty_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PROVIDER] NOCHECK CONSTRAINT fpk_provider_gender_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PROVIDER] NOCHECK CONSTRAINT fpk_provider_specialty_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PROVIDER] NOCHECK CONSTRAINT fpk_provider_gender_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] NOCHECK CONSTRAINT fpk_payer_plan_period_payer_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] NOCHECK CONSTRAINT fpk_payer_plan_period_payer_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] NOCHECK CONSTRAINT fpk_payer_plan_period_plan_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] NOCHECK CONSTRAINT fpk_payer_plan_period_plan_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] NOCHECK CONSTRAINT fpk_payer_plan_period_sponsor_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] NOCHECK CONSTRAINT fpk_payer_plan_period_sponsor_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] NOCHECK CONSTRAINT fpk_payer_plan_period_stop_reason_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] NOCHECK CONSTRAINT fpk_payer_plan_period_stop_reason_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[COST] NOCHECK CONSTRAINT fpk_cost_cost_domain_id;
ALTER TABLE [$(CDM_SCHEMA)].[COST] NOCHECK CONSTRAINT fpk_cost_cost_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[COST] NOCHECK CONSTRAINT fpk_cost_currency_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[COST] NOCHECK CONSTRAINT fpk_cost_revenue_code_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[COST] NOCHECK CONSTRAINT fpk_cost_drg_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[DRUG_ERA] NOCHECK CONSTRAINT fpk_drug_era_drug_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[DOSE_ERA] NOCHECK CONSTRAINT fpk_dose_era_drug_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DOSE_ERA] NOCHECK CONSTRAINT fpk_dose_era_unit_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[CONDITION_ERA] NOCHECK CONSTRAINT fpk_condition_era_condition_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[EPISODE] NOCHECK CONSTRAINT fpk_episode_episode_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[EPISODE] NOCHECK CONSTRAINT fpk_episode_episode_object_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[EPISODE] NOCHECK CONSTRAINT fpk_episode_episode_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[EPISODE] NOCHECK CONSTRAINT fpk_episode_episode_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[METADATA] NOCHECK CONSTRAINT fpk_metadata_metadata_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[METADATA] NOCHECK CONSTRAINT fpk_metadata_metadata_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[METADATA] NOCHECK CONSTRAINT fpk_metadata_value_as_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[CDM_SOURCE] NOCHECK CONSTRAINT fpk_cdm_source_cdm_version_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[SOURCE_TO_CONCEPT_MAP] NOCHECK CONSTRAINT fpk_source_to_concept_map_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[SOURCE_TO_CONCEPT_MAP] NOCHECK CONSTRAINT fpk_source_to_concept_map_target_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[SOURCE_TO_CONCEPT_MAP] NOCHECK CONSTRAINT fpk_source_to_concept_map_target_vocabulary_id;

SET XACT_ABORT ON;
BEGIN TRAN;

-- 1) CDM 데이터 삭제 (FK 역순)
DELETE FROM [$(CDM_SCHEMA)].[CONCEPT_ANCESTOR];
DELETE FROM [$(CDM_SCHEMA)].[CONCEPT_RELATIONSHIP];
DELETE FROM [$(CDM_SCHEMA)].[CONCEPT_SYNONYM];
DELETE FROM [$(CDM_SCHEMA)].[DRUG_STRENGTH];
DELETE FROM [$(CDM_SCHEMA)].[CONCEPT];
DELETE FROM [$(CDM_SCHEMA)].[RELATIONSHIP];
DELETE FROM [$(CDM_SCHEMA)].[CONCEPT_CLASS];
DELETE FROM [$(CDM_SCHEMA)].[VOCABULARY];
DELETE FROM [$(CDM_SCHEMA)].[DOMAIN];

-- 2) Staging -> CDM 이관 (FK 충족 순서)
INSERT INTO [$(CDM_SCHEMA)].[DOMAIN] (domain_id,domain_name,domain_concept_id)
SELECT LTRIM(RTRIM(domain_id)), LTRIM(RTRIM(domain_name)), TRY_CONVERT(INT, domain_concept_id)
FROM [$(STG_SCHEMA)].[DOMAIN];

INSERT INTO [$(CDM_SCHEMA)].[VOCABULARY] (vocabulary_id,vocabulary_name,vocabulary_reference,vocabulary_version,vocabulary_concept_id)
SELECT LTRIM(RTRIM(vocabulary_id)), LTRIM(RTRIM(vocabulary_name)), LTRIM(RTRIM(vocabulary_reference)), LTRIM(RTRIM(vocabulary_version)), TRY_CONVERT(INT, vocabulary_concept_id)
FROM [$(STG_SCHEMA)].[VOCABULARY];

INSERT INTO [$(CDM_SCHEMA)].[CONCEPT_CLASS] (concept_class_id,concept_class_name,concept_class_concept_id)
SELECT LTRIM(RTRIM(concept_class_id)), LTRIM(RTRIM(concept_class_name)), TRY_CONVERT(INT, concept_class_concept_id)
FROM [$(STG_SCHEMA)].[CONCEPT_CLASS];

INSERT INTO [$(CDM_SCHEMA)].[CONCEPT] (concept_id,concept_name,domain_id,vocabulary_id,concept_class_id,standard_concept,concept_code,valid_start_date,valid_end_date,invalid_reason)
SELECT TRY_CONVERT(INT, concept_id), LTRIM(RTRIM(concept_name)), LTRIM(RTRIM(domain_id)), LTRIM(RTRIM(vocabulary_id)), LTRIM(RTRIM(concept_class_id)), NULLIF(LTRIM(RTRIM(standard_concept)),''), LTRIM(RTRIM(concept_code)), TRY_CONVERT(DATE, valid_start_date), TRY_CONVERT(DATE, valid_end_date), NULLIF(LTRIM(RTRIM(invalid_reason)), '')
FROM [$(STG_SCHEMA)].[CONCEPT];

INSERT INTO [$(CDM_SCHEMA)].[RELATIONSHIP] (relationship_id,relationship_name,is_hierarchical,defines_ancestry,reverse_relationship_id,relationship_concept_id)
SELECT LTRIM(RTRIM(relationship_id)), LTRIM(RTRIM(relationship_name)), LTRIM(RTRIM(is_hierarchical)), LTRIM(RTRIM(defines_ancestry)), LTRIM(RTRIM(reverse_relationship_id)), TRY_CONVERT(INT, relationship_concept_id)
FROM [$(STG_SCHEMA)].[RELATIONSHIP];

INSERT INTO [$(CDM_SCHEMA)].[CONCEPT_SYNONYM] (concept_id,concept_synonym_name,language_concept_id)
SELECT TRY_CONVERT(INT, concept_id), LTRIM(RTRIM(concept_synonym_name)), TRY_CONVERT(INT, language_concept_id)
FROM [$(STG_SCHEMA)].[CONCEPT_SYNONYM];

INSERT INTO [$(CDM_SCHEMA)].[CONCEPT_RELATIONSHIP] (concept_id_1,concept_id_2,relationship_id,valid_start_date,valid_end_date,invalid_reason)
SELECT TRY_CONVERT(INT, concept_id_1), TRY_CONVERT(INT, concept_id_2), LTRIM(RTRIM(relationship_id)), TRY_CONVERT(DATE, valid_start_date), TRY_CONVERT(DATE, valid_end_date), NULLIF(LTRIM(RTRIM(invalid_reason)), '')
FROM [$(STG_SCHEMA)].[CONCEPT_RELATIONSHIP];

INSERT INTO [$(CDM_SCHEMA)].[DRUG_STRENGTH] (drug_concept_id,ingredient_concept_id,amount_value,amount_unit_concept_id,numerator_value,numerator_unit_concept_id,denominator_value,denominator_unit_concept_id,box_size,valid_start_date,valid_end_date,invalid_reason)
SELECT TRY_CONVERT(INT, drug_concept_id), TRY_CONVERT(INT, ingredient_concept_id), TRY_CONVERT(FLOAT, amount_value), TRY_CONVERT(INT, amount_unit_concept_id), TRY_CONVERT(FLOAT, numerator_value), TRY_CONVERT(INT, numerator_unit_concept_id), TRY_CONVERT(FLOAT, denominator_value), TRY_CONVERT(INT, denominator_unit_concept_id), TRY_CONVERT(INT, box_size), TRY_CONVERT(DATE, valid_start_date), TRY_CONVERT(DATE, valid_end_date), NULLIF(LTRIM(RTRIM(invalid_reason)), '')
FROM [$(STG_SCHEMA)].[DRUG_STRENGTH];

INSERT INTO [$(CDM_SCHEMA)].[CONCEPT_ANCESTOR] (ancestor_concept_id,descendant_concept_id,min_levels_of_separation,max_levels_of_separation)
SELECT TRY_CONVERT(INT, ancestor_concept_id), TRY_CONVERT(INT, descendant_concept_id), TRY_CONVERT(INT, min_levels_of_separation), TRY_CONVERT(INT, max_levels_of_separation)
FROM [$(STG_SCHEMA)].[CONCEPT_ANCESTOR];

COMMIT;

ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT] CHECK CONSTRAINT fpk_concept_domain_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT] CHECK CONSTRAINT fpk_concept_vocabulary_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT] CHECK CONSTRAINT fpk_concept_concept_class_id;
ALTER TABLE [$(CDM_SCHEMA)].[VOCABULARY] CHECK CONSTRAINT fpk_vocabulary_vocabulary_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DOMAIN] CHECK CONSTRAINT fpk_domain_domain_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT_CLASS] CHECK CONSTRAINT fpk_concept_class_concept_class_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT_RELATIONSHIP] CHECK CONSTRAINT fpk_concept_relationship_concept_id_1;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT_RELATIONSHIP] CHECK CONSTRAINT fpk_concept_relationship_concept_id_2;
ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT_RELATIONSHIP] CHECK CONSTRAINT fpk_concept_relationship_relationship_id;
ALTER TABLE [$(CDM_SCHEMA)].[RELATIONSHIP] CHECK CONSTRAINT fpk_relationship_relationship_concept_id;
--   ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT_SYNONYM] CHECK CONSTRAINT fpk_concept_synonym_concept_id;
--   ALTER TABLE [$(CDM_SCHEMA)].[CONCEPT_SYNONYM] CHECK CONSTRAINT fpk_concept_synonym_language_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_STRENGTH] CHECK CONSTRAINT fpk_drug_strength_drug_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_STRENGTH] CHECK CONSTRAINT fpk_drug_strength_ingredient_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_STRENGTH] CHECK CONSTRAINT fpk_drug_strength_amount_unit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_STRENGTH] CHECK CONSTRAINT fpk_drug_strength_numerator_unit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_STRENGTH] CHECK CONSTRAINT fpk_drug_strength_denominator_unit_concept_id;

-- CDM 데이터 테이블 → Vocabulary 참조 FKs 재활성화
ALTER TABLE [$(CDM_SCHEMA)].[PERSON] CHECK CONSTRAINT fpk_person_gender_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PERSON] CHECK CONSTRAINT fpk_person_race_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PERSON] CHECK CONSTRAINT fpk_person_ethnicity_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PERSON] CHECK CONSTRAINT fpk_person_gender_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PERSON] CHECK CONSTRAINT fpk_person_race_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PERSON] CHECK CONSTRAINT fpk_person_ethnicity_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION_PERIOD] CHECK CONSTRAINT fpk_observation_period_period_type_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[VISIT_OCCURRENCE] CHECK CONSTRAINT fpk_visit_occurrence_visit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_OCCURRENCE] CHECK CONSTRAINT fpk_visit_occurrence_visit_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_OCCURRENCE] CHECK CONSTRAINT fpk_visit_occurrence_visit_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_OCCURRENCE] CHECK CONSTRAINT fpk_visit_occurrence_admitted_from_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_OCCURRENCE] CHECK CONSTRAINT fpk_visit_occurrence_discharged_to_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[VISIT_DETAIL] CHECK CONSTRAINT fpk_visit_detail_visit_detail_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_DETAIL] CHECK CONSTRAINT fpk_visit_detail_visit_detail_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_DETAIL] CHECK CONSTRAINT fpk_visit_detail_visit_detail_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_DETAIL] CHECK CONSTRAINT fpk_visit_detail_admitted_from_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[VISIT_DETAIL] CHECK CONSTRAINT fpk_visit_detail_discharged_to_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[CONDITION_OCCURRENCE] CHECK CONSTRAINT fpk_condition_occurrence_condition_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONDITION_OCCURRENCE] CHECK CONSTRAINT fpk_condition_occurrence_condition_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONDITION_OCCURRENCE] CHECK CONSTRAINT fpk_condition_occurrence_condition_status_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[CONDITION_OCCURRENCE] CHECK CONSTRAINT fpk_condition_occurrence_condition_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[DRUG_EXPOSURE] CHECK CONSTRAINT fpk_drug_exposure_drug_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_EXPOSURE] CHECK CONSTRAINT fpk_drug_exposure_drug_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_EXPOSURE] CHECK CONSTRAINT fpk_drug_exposure_route_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DRUG_EXPOSURE] CHECK CONSTRAINT fpk_drug_exposure_drug_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[PROCEDURE_OCCURRENCE] CHECK CONSTRAINT fpk_procedure_occurrence_procedure_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PROCEDURE_OCCURRENCE] CHECK CONSTRAINT fpk_procedure_occurrence_procedure_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PROCEDURE_OCCURRENCE] CHECK CONSTRAINT fpk_procedure_occurrence_modifier_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PROCEDURE_OCCURRENCE] CHECK CONSTRAINT fpk_procedure_occurrence_procedure_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[DEVICE_EXPOSURE] CHECK CONSTRAINT fpk_device_exposure_device_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DEVICE_EXPOSURE] CHECK CONSTRAINT fpk_device_exposure_device_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DEVICE_EXPOSURE] CHECK CONSTRAINT fpk_device_exposure_device_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DEVICE_EXPOSURE] CHECK CONSTRAINT fpk_device_exposure_unit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DEVICE_EXPOSURE] CHECK CONSTRAINT fpk_device_exposure_unit_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] CHECK CONSTRAINT fpk_measurement_measurement_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] CHECK CONSTRAINT fpk_measurement_measurement_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] CHECK CONSTRAINT fpk_measurement_operator_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] CHECK CONSTRAINT fpk_measurement_value_as_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] CHECK CONSTRAINT fpk_measurement_unit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] CHECK CONSTRAINT fpk_measurement_measurement_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] CHECK CONSTRAINT fpk_measurement_unit_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[MEASUREMENT] CHECK CONSTRAINT fpk_measurement_meas_event_field_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] CHECK CONSTRAINT fpk_observation_observation_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] CHECK CONSTRAINT fpk_observation_observation_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] CHECK CONSTRAINT fpk_observation_value_as_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] CHECK CONSTRAINT fpk_observation_qualifier_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] CHECK CONSTRAINT fpk_observation_unit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] CHECK CONSTRAINT fpk_observation_observation_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[OBSERVATION] CHECK CONSTRAINT fpk_observation_obs_event_field_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[DEATH] CHECK CONSTRAINT fpk_death_death_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DEATH] CHECK CONSTRAINT fpk_death_cause_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DEATH] CHECK CONSTRAINT fpk_death_cause_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[NOTE] CHECK CONSTRAINT fpk_note_note_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[NOTE] CHECK CONSTRAINT fpk_note_note_class_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[NOTE] CHECK CONSTRAINT fpk_note_encoding_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[NOTE] CHECK CONSTRAINT fpk_note_language_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[NOTE] CHECK CONSTRAINT fpk_note_note_event_field_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[NOTE_NLP] CHECK CONSTRAINT fpk_note_nlp_section_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[NOTE_NLP] CHECK CONSTRAINT fpk_note_nlp_note_nlp_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[NOTE_NLP] CHECK CONSTRAINT fpk_note_nlp_note_nlp_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[SPECIMEN] CHECK CONSTRAINT fpk_specimen_specimen_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[SPECIMEN] CHECK CONSTRAINT fpk_specimen_specimen_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[SPECIMEN] CHECK CONSTRAINT fpk_specimen_unit_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[SPECIMEN] CHECK CONSTRAINT fpk_specimen_anatomic_site_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[SPECIMEN] CHECK CONSTRAINT fpk_specimen_disease_status_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[FACT_RELATIONSHIP] CHECK CONSTRAINT fpk_fact_relationship_domain_concept_id_1;
ALTER TABLE [$(CDM_SCHEMA)].[FACT_RELATIONSHIP] CHECK CONSTRAINT fpk_fact_relationship_domain_concept_id_2;
ALTER TABLE [$(CDM_SCHEMA)].[FACT_RELATIONSHIP] CHECK CONSTRAINT fpk_fact_relationship_relationship_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[LOCATION] CHECK CONSTRAINT fpk_location_country_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[CARE_SITE] CHECK CONSTRAINT fpk_care_site_place_of_service_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[PROVIDER] CHECK CONSTRAINT fpk_provider_specialty_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PROVIDER] CHECK CONSTRAINT fpk_provider_gender_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PROVIDER] CHECK CONSTRAINT fpk_provider_specialty_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PROVIDER] CHECK CONSTRAINT fpk_provider_gender_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] CHECK CONSTRAINT fpk_payer_plan_period_payer_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] CHECK CONSTRAINT fpk_payer_plan_period_payer_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] CHECK CONSTRAINT fpk_payer_plan_period_plan_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] CHECK CONSTRAINT fpk_payer_plan_period_plan_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] CHECK CONSTRAINT fpk_payer_plan_period_sponsor_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] CHECK CONSTRAINT fpk_payer_plan_period_sponsor_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] CHECK CONSTRAINT fpk_payer_plan_period_stop_reason_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[PAYER_PLAN_PERIOD] CHECK CONSTRAINT fpk_payer_plan_period_stop_reason_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[COST] CHECK CONSTRAINT fpk_cost_cost_domain_id;
ALTER TABLE [$(CDM_SCHEMA)].[COST] CHECK CONSTRAINT fpk_cost_cost_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[COST] CHECK CONSTRAINT fpk_cost_currency_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[COST] CHECK CONSTRAINT fpk_cost_revenue_code_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[COST] CHECK CONSTRAINT fpk_cost_drg_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[DRUG_ERA] CHECK CONSTRAINT fpk_drug_era_drug_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[DOSE_ERA] CHECK CONSTRAINT fpk_dose_era_drug_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[DOSE_ERA] CHECK CONSTRAINT fpk_dose_era_unit_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[CONDITION_ERA] CHECK CONSTRAINT fpk_condition_era_condition_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[EPISODE] CHECK CONSTRAINT fpk_episode_episode_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[EPISODE] CHECK CONSTRAINT fpk_episode_episode_object_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[EPISODE] CHECK CONSTRAINT fpk_episode_episode_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[EPISODE] CHECK CONSTRAINT fpk_episode_episode_source_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[METADATA] CHECK CONSTRAINT fpk_metadata_metadata_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[METADATA] CHECK CONSTRAINT fpk_metadata_metadata_type_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[METADATA] CHECK CONSTRAINT fpk_metadata_value_as_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[CDM_SOURCE] CHECK CONSTRAINT fpk_cdm_source_cdm_version_concept_id;

ALTER TABLE [$(CDM_SCHEMA)].[SOURCE_TO_CONCEPT_MAP] CHECK CONSTRAINT fpk_source_to_concept_map_source_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[SOURCE_TO_CONCEPT_MAP] CHECK CONSTRAINT fpk_source_to_concept_map_target_concept_id;
ALTER TABLE [$(CDM_SCHEMA)].[SOURCE_TO_CONCEPT_MAP] CHECK CONSTRAINT fpk_source_to_concept_map_target_vocabulary_id;

-- 3) Staging 테이블 정리 (실패 시 에러 발생)
DROP TABLE [$(STG_SCHEMA)].[CONCEPT_ANCESTOR];
DROP TABLE [$(STG_SCHEMA)].[CONCEPT_RELATIONSHIP];
DROP TABLE [$(STG_SCHEMA)].[CONCEPT_SYNONYM];
DROP TABLE [$(STG_SCHEMA)].[DRUG_STRENGTH];
DROP TABLE [$(STG_SCHEMA)].[CONCEPT];
DROP TABLE [$(STG_SCHEMA)].[RELATIONSHIP];
DROP TABLE [$(STG_SCHEMA)].[CONCEPT_CLASS];
DROP TABLE [$(STG_SCHEMA)].[VOCABULARY];
DROP TABLE [$(STG_SCHEMA)].[DOMAIN];


