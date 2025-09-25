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


