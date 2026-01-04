SET NOCOUNT ON;

-- 공통 맵/소스 CTE
;WITH person_map AS (
  SELECT ptntidno, person_id FROM [$(StagingSchema)].person_id_map
), visit_map AS (
  SELECT ptntidno, [date], [source], visit_occurrence_id FROM [$(StagingSchema)].visit_occurrence_map
), meas_map AS (
  SELECT
    UPPER(LTRIM(RTRIM(LABNM))) AS LABNM,
    UPPER(LTRIM(RTRIM(ItemName))) AS ItemName,
    common_concept_id,
    right_concept_id,
    left_concept_id
  FROM [$(StagingSchema)].measurement_vocabulary_map
), lab_master AS (
  SELECT 
    m.LABID,
    UPPER(LTRIM(RTRIM(m.LABNM))) AS LABNM_NORM,
    m.LABNM,
    v.ItemNumber,
    UPPER(LTRIM(RTRIM(v.ItemName))) AS ItemName_NORM,
    v.ItemName,
    v.Symbol
  FROM
    [$(SrcSchema)].[INFLABM] m
  CROSS APPLY (
    VALUES
      ('Item1', m.Item1, m.Symbol1), ('Item2', m.Item2, m.Symbol2), ('Item3', m.Item3, m.Symbol3), ('Item4', m.Item4, m.Symbol4), ('Item5', m.Item5, m.Symbol5),
      ('Item6', m.Item6, m.Symbol6), ('Item7', m.Item7, m.Symbol7), ('Item8', m.Item8, m.Symbol8), ('Item9', m.Item9, m.Symbol9), ('Item10', m.Item10, m.Symbol10),
      ('Item11', m.Item11, m.Symbol11), ('Item12', m.Item12, m.Symbol12), ('Item13', m.Item13, m.Symbol13), ('Item14', m.Item14, m.Symbol14), ('Item15', m.Item15, m.Symbol15),
      ('Item16', m.Item16, m.Symbol16), ('Item17', m.Item17, m.Symbol17), ('Item18', m.Item18, m.Symbol18), ('Item19', m.Item19, m.Symbol19), ('Item20', m.Item20, m.Symbol20),
      ('Item21', m.Item21, m.Symbol21), ('Item22', m.Item22, m.Symbol22), ('Item23', m.Item23, m.Symbol23), ('Item24', m.Item24, m.Symbol24), ('Item25', m.Item25, m.Symbol25),
      ('Item26', m.Item26, m.Symbol26), ('Item27', m.Item27, m.Symbol27), ('Item28', m.Item28, m.Symbol28), ('Item29', m.Item29, m.Symbol29), ('Item30', m.Item30, m.Symbol30),
      ('Item31', m.Item31, m.Symbol31), ('Item32', m.Item32, m.Symbol32), ('Item33', m.Item33, m.Symbol33), ('Item34', m.Item34, m.Symbol34), ('Item35', m.Item35, m.Symbol35),
      ('Item36', m.Item36, m.Symbol36), ('Item37', m.Item37, m.Symbol37), ('Item38', m.Item38, m.Symbol38), ('Item39', m.Item39, m.Symbol39), ('Item40', m.Item40, m.Symbol40)
  ) AS v(ItemNumber, ItemName, Symbol)
  WHERE v.ItemName IS NOT NULL AND LEN(v.ItemName) > 0
), lab_raw AS (
  SELECT 
    t.PTNTIDNO,
    t.REGDATE,
    t.LABID,
    t.LR,
    t.SEQ,
    v.ItemNumber,
    v.ItemValue
  FROM
    [$(SrcSchema)].[INFLABD] t
  CROSS APPLY (
    VALUES
          ('Item1', t.Item1), ('Item2', t.Item2), ('Item3', t.Item3), ('Item4', t.Item4), ('Item5', t.Item5),
          ('Item6', t.Item6), ('Item7', t.Item7), ('Item8', t.Item8), ('Item9', t.Item9), ('Item10', t.Item10),
          ('Item11', t.Item11), ('Item12', t.Item12), ('Item13', t.Item13), ('Item14', t.Item14), ('Item15', t.Item15),
          ('Item16', t.Item16), ('Item17', t.Item17), ('Item18', t.Item18), ('Item19', t.Item19), ('Item20', t.Item20),
          ('Item21', t.Item21), ('Item22', t.Item22), ('Item23', t.Item23), ('Item24', t.Item24), ('Item25', t.Item25),
          ('Item26', t.Item26), ('Item27', t.Item27), ('Item28', t.Item28), ('Item29', t.Item29), ('Item30', t.Item30),
          ('Item31', t.Item31), ('Item32', t.Item32), ('Item33', t.Item33), ('Item34', t.Item34), ('Item35', t.Item35),
          ('Item36', t.Item36), ('Item37', t.Item37), ('Item38', t.Item38), ('Item39', t.Item39), ('Item40', t.Item40)
  ) AS v(ItemNumber, ItemValue)
  WHERE NULLIF(LTRIM(RTRIM(v.ItemValue)), '') IS NOT NULL AND LEN(NULLIF(LTRIM(RTRIM(v.ItemValue)), '')) > 0
), lab_enriched AS (
  SELECT  
    k.measurement_id,
    pm.person_id,
    COALESCE(
      CASE
        WHEN UPPER(LTRIM(RTRIM(NULLIF(LTRIM(RTRIM(t.LR)), '')))) IN ('R','OD','우','RIGHT','RIGHTEYE','RIGHT EYE','OD(우)') THEN mm.left_concept_id
        WHEN UPPER(LTRIM(RTRIM(NULLIF(LTRIM(RTRIM(t.LR)), '')))) IN ('L','OS','좌','LEFT','LEFTEYE','LEFT EYE','OS(좌)') THEN mm.right_concept_id
        ELSE mm.common_concept_id
      END,
      mm.common_concept_id,
      0
    ) AS measurement_concept_id,
    TRY_CONVERT(date, t.REGDATE) AS measurement_date,
    NULL AS measurement_datetime,
    NULL AS measurement_time,
    32817 AS measurement_type_concept_id,
    NULL AS operator_concept_id,
    TRY_CAST(NULLIF(LTRIM(RTRIM(REPLACE(t.ItemValue, ' ', ''))), '') AS FLOAT) AS value_as_number,
    NULL AS value_as_concept_id,
    NULL AS unit_concept_id,
    NULL AS range_low,
    NULL AS range_high,
    NULL AS provider_id,
    vm.visit_occurrence_id,
    NULL AS visit_detail_id,
    CONCAT(m.LABNM, ' - ', m.ItemName, ' - ', m.Symbol, ' - ', NULLIF(LTRIM(RTRIM(t.LR)), '')) AS measurement_source_value,
    NULL AS measurement_source_concept_id,
    NULL AS unit_source_value,
    NULL AS unit_source_concept_id,
    NULLIF(LTRIM(RTRIM(t.ItemValue)), '') AS value_source_value,
    NULL AS measurement_event_id,
    NULL AS meas_event_field_concept_id
  FROM lab_raw t
  JOIN lab_master m
    ON m.LABID = t.LABID AND m.ItemNumber = t.ItemNumber
  LEFT JOIN meas_map mm
    ON m.LABNM_NORM = mm.LABNM COLLATE DATABASE_DEFAULT AND m.ItemName_NORM = mm.ItemName COLLATE DATABASE_DEFAULT
  JOIN person_map pm ON pm.ptntidno = t.PTNTIDNO
  JOIN visit_map vm ON vm.ptntidno = t.PTNTIDNO AND vm.date = t.REGDATE
  JOIN [$(StagingSchema)].measurement_map k
    ON k.ptntidno = t.PTNTIDNO
    AND k.[date] = t.REGDATE
    AND k.[source] = 'LAB'
    AND k.mk_lab_id = CAST(t.LABID AS varchar(20))
    AND k.mk_item_no = CAST(t.ItemNumber AS varchar(10))
    AND k.mk_lr = ISNULL(CAST(t.LR AS varchar(20)), '')
    AND k.mk_seq = ISNULL(CAST(t.SEQ AS varchar(10)), '')
    AND k.mk_serial = 0
    AND k.mk_order = 0
    AND k.map_index = 1
), hira_measurement_map AS (
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(m.LOCAL_CD1 AS varchar(200))))) AS code_norm,
    TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) AS target_concept_id,
    TRY_CONVERT(int, m.SOURCE_CONCEPT_ID)   AS source_concept_id
  FROM [$(StagingSchema)].hira_map m
  WHERE m.TARGET_DOMAIN_ID = 'Measurement'
    AND m.INVALID_REASON IS NULL
    AND TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) IS NOT NULL
), meas_code_meta AS (
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(200))))) AS code_norm
  FROM [$(SrcSchema)].[PICMECHM] p
  WHERE (
    TRY_CONVERT(int, p.[보험분류]) IN (9999)
    OR TRY_CONVERT(int, p.[수익분류]) IN (9999)
  )
  AND TRY_CONVERT(int, p.[수가분류]) <> 3
), target_codes AS (
  SELECT code_norm FROM hira_measurement_map
  UNION
  SELECT code_norm FROM meas_code_meta
), op_raw AS (
  SELECT
    o.PTNTIDNO,
    o.[진료일자] AS svc_date,
    o.[청구코드] AS claim_code,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),'')) AS serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),'')) AS order_no,
    UPPER(LTRIM(RTRIM(CAST(o.[청구코드] AS varchar(200))))) AS normalized_code
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, o.[진료일자]) IS NOT NULL
), ip_raw AS (
  SELECT
    i.PTNTIDNO,
    i.[진료일자] AS svc_date,
    i.[청구코드] AS claim_code,
    0 AS serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),'')) AS order_no,
    UPPER(LTRIM(RTRIM(CAST(i.[청구코드] AS varchar(200))))) AS normalized_code
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
    AND TRY_CONVERT(date, i.[진료일자]) IS NOT NULL
), op_filtered AS (
  SELECT r.*
  FROM op_raw r
  JOIN target_codes tc ON tc.code_norm = r.normalized_code COLLATE DATABASE_DEFAULT
), ip_filtered AS (
  SELECT r.*
  FROM ip_raw r
  JOIN target_codes tc ON tc.code_norm = r.normalized_code COLLATE DATABASE_DEFAULT
), op_enriched AS (
  SELECT
    r.PTNTIDNO AS k_ptntidno, 
    REPLACE(r.svc_date, '-', '') AS k_date, 
    'OP' AS k_src,
    r.serial_no AS k_serial,
    r.order_no AS k_order,
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.svc_date) AS measurement_date,
    NULL AS measurement_datetime,
    NULL AS measurement_time,
    32817 AS measurement_type_concept_id,
    NULL AS operator_concept_id,
    NULL AS value_as_number,
    NULL AS value_as_concept_id,
    NULL AS unit_concept_id,
    NULL AS range_low,
    NULL AS range_high,
    NULL AS provider_id,
    NULL AS visit_detail_id,
    NULLIF(LTRIM(RTRIM(CAST(r.claim_code AS varchar(50)))), '') AS measurement_source_value,
    r.normalized_code,
    NULL AS value_source_value
  FROM op_filtered r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map vm ON vm.ptntidno = r.PTNTIDNO AND vm.[date] = REPLACE(r.svc_date, '-', '') AND vm.[source] = 'OP'
), ip_enriched AS (
  SELECT
    r.PTNTIDNO AS k_ptntidno, 
    REPLACE(r.svc_date, '-', '') AS k_date, 
    'IP' AS k_src,
    r.serial_no AS k_serial,
    r.order_no AS k_order,
    pm.person_id,
    vm.visit_occurrence_id,
    TRY_CONVERT(date, r.svc_date) AS measurement_date,
    NULL AS measurement_datetime,
    NULL AS measurement_time,
    32817 AS measurement_type_concept_id,
    NULL AS operator_concept_id,
    NULL AS value_as_number,
    NULL AS value_as_concept_id,
    NULL AS unit_concept_id,
    NULL AS range_low,
    NULL AS range_high,
    NULL AS provider_id,
    NULL AS visit_detail_id,
    NULLIF(LTRIM(RTRIM(CAST(r.claim_code AS varchar(50)))), '') AS measurement_source_value,
    r.normalized_code,
    NULL AS value_source_value
  FROM ip_filtered r
  JOIN person_map pm ON pm.ptntidno = r.PTNTIDNO
  LEFT JOIN visit_map vm ON vm.ptntidno = r.PTNTIDNO AND vm.[date] = REPLACE(r.svc_date, '-', '') AND vm.[source] = 'IP'
), code_union AS (
  SELECT * FROM op_enriched
  UNION ALL
  SELECT * FROM ip_enriched
), code_mapped AS (
  SELECT
    u.*,
    hm.target_concept_id,
    hm.source_concept_id,
    ROW_NUMBER() OVER (
         PARTITION BY u.k_ptntidno, u.k_date, u.k_src, u.k_serial, u.k_order 
         ORDER BY hm.target_concept_id
       ) AS rn
  FROM code_union u
  LEFT JOIN hira_measurement_map hm ON hm.code_norm = u.normalized_code COLLATE DATABASE_DEFAULT
), code_enriched AS (
  SELECT
    k.measurement_id,
    u.person_id,
    COALESCE(u.target_concept_id, 0) AS measurement_concept_id,
    u.measurement_date,
    u.measurement_datetime,
    u.measurement_time,
    u.measurement_type_concept_id,
    u.operator_concept_id,
    u.value_as_number,
    u.value_as_concept_id,
    u.unit_concept_id,
    u.range_low,
    u.range_high,
    u.provider_id,
    u.visit_occurrence_id,
    u.visit_detail_id,
    u.measurement_source_value,
    u.source_concept_id AS measurement_source_concept_id,
    NULL AS unit_source_value,
    NULL AS unit_source_concept_id,
    u.value_source_value,
    NULL AS measurement_event_id,
    NULL AS meas_event_field_concept_id
  FROM code_mapped u
  JOIN [$(StagingSchema)].measurement_map k
    ON k.ptntidno = u.k_ptntidno
    AND k.[date] = u.k_date
    AND k.[source] = u.k_src
    AND k.mk_lab_id = ''
    AND k.mk_item_no = ''
    AND k.mk_lr = ''
    AND k.mk_seq = ''
    AND k.mk_serial = u.k_serial
    AND k.mk_order = u.k_order
    AND k.map_index = u.rn
)
SELECT * FROM lab_enriched
UNION ALL
SELECT * FROM code_enriched;
