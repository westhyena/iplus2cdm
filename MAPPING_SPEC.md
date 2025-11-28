# iPlus EMR to OMOP CDM 매핑 명세서

본 문서는 iPlus EMR 데이터를 OMOP Common Data Model (CDM)로 변환하기 위한 매핑 명세서입니다.
`etl-sql` 폴더 내의 변환 로직을 기반으로 작성되었습니다.

## 1. PERSON (환자 정보)

**소스 테이블:** `PMCPTNT`

| 컬럼명 | 컬럼 타입 | 필수 여부 | 소스 | 비고 |
| :--- | :--- | :--- | :--- | :--- |
| person_id | Integer | Y | `person_id_map` | `ROW_NUMBER()`로 생성된 ID 매핑 사용 |
| gender_concept_id | Integer | Y | `PTNTSEXX` | 남(M,1) -> 8507, 여(F,2) -> 8532, 그외 -> 8551 |
| year_of_birth | Integer | Y | `PTNTBITH` | 생년월일 앞 4자리 |
| month_of_birth | Integer | Y | `PTNTBITH` | 생년월일 5~6번째 자리 |
| day_of_birth | Integer | Y | `PTNTBITH` | 생년월일 7~8번째 자리 |
| birth_datetime | Datetime | N | `PTNTBITH` | 생년월일 + '00:00:00' |
| race_concept_id | Integer | Y | - | 0 (Unknown) |
| ethnicity_concept_id | Integer | Y | - | 0 (Unknown) |
| location_id | Integer | N | - | NULL |
| provider_id | Integer | N | - | NULL |
| care_site_id | Integer | N | - | NULL |
| person_source_value | String | N | `PTNTIDNO` | 환자등록번호 |
| gender_source_value | String | N | `PTNTSEXX` | 성별 원본 값 |
| gender_source_concept_id | Integer | N | - | NULL |
| race_source_value | String | N | - | NULL |
| race_source_concept_id | Integer | N | - | NULL |
| ethnicity_source_value | String | N | - | NULL |
| ethnicity_source_concept_id | Integer | N | - | NULL |

## 2. VISIT_OCCURRENCE (방문 정보)

**소스 테이블:** `PMOOTPTH` (외래), `PMIINPTH` (입원)

| 컬럼명 | 컬럼 타입 | 필수 여부 | 소스 | 비고 |
| :--- | :--- | :--- | :--- | :--- |
| visit_occurrence_id | Integer | Y | `visit_occurrence_map` | `ROW_NUMBER()`로 생성된 ID 매핑 사용 |
| person_id | Integer | Y | `person_id_map` | 환자 ID 매핑 |
| visit_concept_id | Integer | Y | `OTPTMETP` (외래), 입원여부 | 외래: 응급('E') 포함시 9203(ER), 아니면 9201(OP)<br>입원: 9202(IP) |
| visit_start_date | Date | Y | `OTPTMDDT` / `INPTADDT` | 진료/입원 일자 |
| visit_start_datetime | Datetime | Y | `OTPTMDTM` / `INPTADTM` | 진료/입원 일자 + 시간(HHMM) 결합 (시간 없으면 00:00) |
| visit_end_date | Date | Y | `OTPTMDDT` / `INPTDSDT` | 진료/퇴원 일자 |
| visit_end_datetime | Datetime | Y | `OTPTMDTM` / `INPTDSTM` | 진료/퇴원 일자 + 시간(HHMM) 결합 (시간 없으면 00:00) |
| visit_type_concept_id | Integer | Y | - | 32817 (EHR) |
| provider_id | Integer | N | - | NULL |
| care_site_id | Integer | N | - | NULL |
| visit_source_value | String | N | `OTPTMETP` | 외래: 진료과목코드 등 (Aggregated)<br>입원: NULL |
| visit_source_concept_id | Integer | N | - | NULL |
| admitted_from_concept_id | Integer | N | `INPTADRT` | 입원경로 매핑 (`ADMIT_FROM` vocabulary) |
| admitted_from_source_value | String | N | `INPTADRT` | 입원경로 원본 값 |
| discharged_to_concept_id | Integer | N | `INPTDSRS` | 퇴원형태 매핑 (`DISCHARGE_TO` vocabulary) |
| discharged_to_source_value | String | N | `INPTDSRS` | 퇴원형태 원본 값 |
| preceding_visit_occurrence_id | Integer | N | - | NULL |

## 3. CONDITION_OCCURRENCE (진단 정보)

**소스 테이블:** `OCSDISE` (외래), `OCSDISEI` (입원)

| 컬럼명 | 컬럼 타입 | 필수 여부 | 소스 | 비고 |
| :--- | :--- | :--- | :--- | :--- |
| condition_occurrence_id | Integer | Y | Sequence | 자동 증가 ID |
| person_id | Integer | Y | `person_id_map` | 환자 ID 매핑 |
| condition_concept_id | Integer | Y | `상병코드` | `condition_vocabulary_map` 매핑 |
| condition_start_date | Date | Y | `진료일자` | |
| condition_start_datetime | Datetime | N | - | NULL |
| condition_end_date | Date | N | `visit_end_date` | 방문 종료일 사용 (없으면 시작일) |
| condition_end_datetime | Datetime | N | - | NULL |
| condition_type_concept_id | Integer | Y | - | 32817 (EHR) |
| condition_status_concept_id | Integer | N | `row_i` | 0이면 32902(주상병), 그외 32908(부상병) |
| stop_reason | String | N | - | NULL |
| provider_id | Integer | N | - | NULL |
| visit_occurrence_id | Integer | N | `visit_occurrence_map` | 방문 ID 매핑 |
| visit_detail_id | Integer | N | - | NULL |
| condition_source_value | String | N | `상병코드` | 원본 상병코드 |
| condition_source_concept_id | Integer | N | `상병코드` | `condition_vocabulary_map` 소스 컨셉 ID |
| condition_status_source_value | String | N | - | NULL |

## 4. DRUG_EXPOSURE (약물 처방 정보)

**소스 테이블:** `OCSSLIP` (외래), `OCSSLIPI` (입원)
**필터:** `수가분류` = 3

| 컬럼명 | 컬럼 타입 | 필수 여부 | 소스 | 비고 |
| :--- | :--- | :--- | :--- | :--- |
| drug_exposure_id | Integer | Y | `drug_exposure_map` | `ROW_NUMBER()`로 생성된 ID 매핑 사용 |
| person_id | Integer | Y | `person_id_map` | 환자 ID 매핑 |
| drug_concept_id | Integer | Y | `청구코드` | `drug_vocabulary_map` 또는 `hira_map`(Drug) 매핑 |
| drug_exposure_start_date | Date | Y | `진료일자` | |
| drug_exposure_start_datetime | Datetime | N | - | NULL |
| drug_exposure_end_date | Date | Y | `진료일자`, `투여일수` | 진료일자 + 투여일수 - 1 |
| drug_exposure_end_datetime | Datetime | N | - | NULL |
| verbatim_end_date | Date | N | - | NULL |
| drug_type_concept_id | Integer | Y | - | 32817 (EHR) |
| stop_reason | String | N | - | NULL |
| refills | Integer | N | - | NULL |
| quantity | Float | N | `투여량`, `투여횟수` | 투여량 * 투여횟수 |
| days_supply | Integer | N | `투여일수` | |
| sig | String | N | - | NULL |
| route_concept_id | Integer | N | - | NULL |
| lot_number | String | N | - | NULL |
| provider_id | Integer | N | - | NULL |
| visit_occurrence_id | Integer | N | `visit_occurrence_map` | 방문 ID 매핑 |
| visit_detail_id | Integer | N | - | NULL |
| drug_source_value | String | N | `청구코드` | |
| drug_source_concept_id | Integer | N | `청구코드` | 매핑 테이블의 소스 컨셉 ID |
| route_source_value | String | N | - | NULL |
| dose_unit_source_value | String | N | - | NULL |

## 5. MEASUREMENT (검사/측정 정보)

**소스 테이블 1:** `INFLABD` (진단검사 결과)
**소스 테이블 2:** `OCSSLIP`, `OCSSLIPI` (청구코드 중 Measurement 도메인)

| 컬럼명 | 컬럼 타입 | 필수 여부 | 소스 | 비고 |
| :--- | :--- | :--- | :--- | :--- |
| measurement_id | Integer | Y | Sequence | 자동 증가 ID |
| person_id | Integer | Y | `person_id_map` | 환자 ID 매핑 |
| measurement_concept_id | Integer | Y | `LABNM`+`ItemName` / `청구코드` | `measurement_vocabulary_map` (좌/우 구분 포함) 또는 `hira_map` |
| measurement_date | Date | Y | `REGDATE` / `진료일자` | |
| measurement_datetime | Datetime | N | - | NULL |
| measurement_time | String | N | - | NULL |
| measurement_type_concept_id | Integer | Y | - | 32817 (EHR) |
| operator_concept_id | Integer | N | - | NULL |
| value_as_number | Float | N | `ItemValue` | 숫자형 변환 가능 시 값 (청구코드는 NULL) |
| value_as_concept_id | Integer | N | - | NULL |
| unit_concept_id | Integer | N | - | NULL |
| range_low | Float | N | - | NULL |
| range_high | Float | N | - | NULL |
| provider_id | Integer | N | - | NULL |
| visit_occurrence_id | Integer | N | `visit_occurrence_map` | 방문 ID 매핑 |
| visit_detail_id | Integer | N | - | NULL |
| measurement_source_value | String | N | `LABNM`-`ItemName`... / `청구코드` | 소스 식별 값 |
| measurement_source_concept_id | Integer | N | - / `청구코드` | `hira_map` 소스 컨셉 ID (청구코드인 경우) |
| unit_source_value | String | N | - | NULL |
| unit_source_concept_id | Integer | N | - | NULL |
| value_source_value | String | N | `ItemValue` | 결과값 원본 |
| measurement_event_id | Integer | N | - | NULL |
| meas_event_field_concept_id | Integer | N | - | NULL |

## 6. OBSERVATION (관찰 정보)

**소스 테이블:** `OCSSLIP`, `OCSSLIPI`
**필터:** `hira_map`(Observation) 또는 `PICMECHM`(보험/수익분류 9999)

| 컬럼명 | 컬럼 타입 | 필수 여부 | 소스 | 비고 |
| :--- | :--- | :--- | :--- | :--- |
| observation_id | Integer | Y | Sequence | 자동 증가 ID |
| person_id | Integer | Y | `person_id_map` | 환자 ID 매핑 |
| observation_concept_id | Integer | Y | `청구코드` | `hira_map` 매핑 |
| observation_date | Date | Y | `진료일자` | |
| observation_datetime | Datetime | N | - | NULL |
| observation_type_concept_id | Integer | Y | - | 32817 (EHR) |
| value_as_number | Float | N | - | NULL |
| value_as_string | String | N | - | NULL |
| value_as_concept_id | Integer | N | - | NULL |
| qualifier_concept_id | Integer | N | - | NULL |
| unit_concept_id | Integer | N | - | NULL |
| provider_id | Integer | N | - | NULL |
| visit_occurrence_id | Integer | N | `visit_occurrence_map` | 방문 ID 매핑 |
| visit_detail_id | Integer | N | - | NULL |
| observation_source_value | String | N | `청구코드` | |
| observation_source_concept_id | Integer | N | `청구코드` | `hira_map` 소스 컨셉 ID |
| unit_source_value | String | N | - | NULL |
| qualifier_source_value | String | N | - | NULL |
| value_source_value | String | N | - | NULL |
| observation_event_id | Integer | N | - | NULL |
| obs_event_field_concept_id | Integer | N | - | NULL |

## 7. PROCEDURE_OCCURRENCE (시술/처치 정보)

**소스 테이블:** `OCSSLIP`, `OCSSLIPI`
**필터:** `hira_map`(Procedure) 또는 `PICMECHM`(보험분류 26,27 / 수익분류 9,10)

| 컬럼명 | 컬럼 타입 | 필수 여부 | 소스 | 비고 |
| :--- | :--- | :--- | :--- | :--- |
| procedure_occurrence_id | Integer | Y | Sequence | 자동 증가 ID |
| person_id | Integer | Y | `person_id_map` | 환자 ID 매핑 |
| procedure_concept_id | Integer | Y | `청구코드` | `hira_map` 매핑 |
| procedure_date | Date | Y | `진료일자` | |
| procedure_datetime | Datetime | N | - | NULL |
| procedure_type_concept_id | Integer | Y | - | 32817 (EHR) |
| modifier_concept_id | Integer | N | - | NULL |
| quantity | Integer | N | - | NULL |
| provider_id | Integer | N | - | NULL |
| visit_occurrence_id | Integer | N | `visit_occurrence_map` | 방문 ID 매핑 |
| visit_detail_id | Integer | N | - | NULL |
| procedure_source_value | String | N | `청구코드` | |
| procedure_source_concept_id | Integer | N | `청구코드` | `hira_map` 소스 컨셉 ID |
| modifier_source_value | String | N | - | NULL |

## 8. DEVICE_EXPOSURE (의료기기 사용 정보)

**소스 테이블:** `OCSSLIP`, `OCSSLIPI`
**필터:** `hira_map`(Device) 또는 `PICMECHM`(보험/수익분류 9999)

| 컬럼명 | 컬럼 타입 | 필수 여부 | 소스 | 비고 |
| :--- | :--- | :--- | :--- | :--- |
| device_exposure_id | Integer | Y | Sequence | 자동 증가 ID |
| person_id | Integer | Y | `person_id_map` | 환자 ID 매핑 |
| device_concept_id | Integer | Y | `청구코드` | `hira_map` 매핑 |
| device_exposure_start_date | Date | Y | `진료일자` | |
| device_exposure_start_datetime | Datetime | N | - | NULL |
| device_exposure_end_date | Date | N | - | NULL |
| device_exposure_end_datetime | Datetime | N | - | NULL |
| device_type_concept_id | Integer | Y | - | 32817 (EHR) |
| unique_device_id | String | N | - | NULL |
| production_id | String | N | - | NULL |
| quantity | Integer | N | - | NULL |
| provider_id | Integer | N | - | NULL |
| visit_occurrence_id | Integer | N | `visit_occurrence_map` | 방문 ID 매핑 |
| visit_detail_id | Integer | N | - | NULL |
| device_source_value | String | N | `청구코드` | |
| device_source_concept_id | Integer | N | `청구코드` | `hira_map` 소스 컨셉 ID |
| unit_concept_id | Integer | N | - | NULL |
| unit_source_value | String | N | - | NULL |
| unit_source_concept_id | Integer | N | - | NULL |

## 9. COST (비용 정보)

**소스 테이블:** `OCSSLIP`, `OCSSLIPI`
**연결:** Procedure, Drug, Device, Observation 테이블의 ID와 연결

| 컬럼명 | 컬럼 타입 | 필수 여부 | 소스 | 비고 |
| :--- | :--- | :--- | :--- | :--- |
| cost_id | Integer | Y | Sequence | 자동 증가 ID |
| cost_event_id | Integer | Y | 각 도메인 ID | Procedure/Drug/Device/Observation ID |
| cost_domain_id | String | Y | - | 'Procedure', 'Drug', 'Device', 'Observation' |
| cost_type_concept_id | Integer | Y | - | 32817 (EHR) |
| currency_concept_id | Integer | Y | - | 44818598 (KRW) |
| total_cost | Float | N | `금액` | |
| payer_plan_period_id | Integer | N | - | NULL |
| amount_allowed | Float | N | - | NULL |
| payer_source_value | String | N | - | NULL |
| revenue_code_concept_id | Integer | N | - | NULL |
| drg_concept_id | Integer | N | - | NULL |
| drg_source_value | String | N | - | NULL |

## 10. OBSERVATION_PERIOD (관찰 기간)

**소스 테이블:** `VISIT_OCCURRENCE` (파생)

| 컬럼명 | 컬럼 타입 | 필수 여부 | 소스 | 비고 |
| :--- | :--- | :--- | :--- | :--- |
| observation_period_id | Integer | Y | Sequence | 자동 증가 ID |
| person_id | Integer | Y | `person_id` | |
| observation_period_start_date | Date | Y | `visit_start_date` | 환자의 최초 방문일 |
| observation_period_end_date | Date | Y | `visit_end_date` | 환자의 마지막 방문일 |
| period_type_concept_id | Integer | Y | - | 32818 (EHR) |
