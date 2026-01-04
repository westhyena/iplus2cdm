SET NOCOUNT ON;

-- 1. LAB Source Keys (INFLABD unpivoted)
-- Logic mirrors etl-sql/extract/extract_measurement.sql
;WITH lab_raw AS (
  SELECT 
    t.PTNTIDNO,
    t.REGDATE,
    t.LABID,
    t.LR,
    t.SEQ, -- Added SEQ
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
  WHERE v.ItemValue IS NOT NULL AND LEN(v.ItemValue) > 0
), lab_keys AS (
  SELECT DISTINCT
    r.PTNTIDNO AS ptntidno,
    r.REGDATE AS [date],
    'LAB' AS [source],
    CAST(r.LABID AS varchar(20)) AS mk_lab_id,
    CAST(r.ItemNumber AS varchar(10)) AS mk_item_no,
    ISNULL(CAST(r.LR AS varchar(20)), '') AS mk_lr,
    ISNULL(CAST(r.SEQ AS varchar(10)), '') AS mk_seq, -- Map SEQ
    0 AS mk_serial,
    0 AS mk_order,
    1 AS map_index 
  FROM lab_raw r
),

-- 2. Claim Source Keys (OP/IP)
-- Filtered by valid measurement codes
hira_measurement_map AS (
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(m.LOCAL_CD1 AS varchar(200))))) AS code_norm,
    TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) AS target_concept_id
  FROM [$(StagingSchema)].hira_map m
  WHERE m.TARGET_DOMAIN_ID = 'Measurement'
    AND m.INVALID_REASON IS NULL
    AND TRY_CONVERT(int, m.TARGET_CONCEPT_ID_1) IS NOT NULL
), 
meas_code_meta AS (
  SELECT DISTINCT
    UPPER(LTRIM(RTRIM(CAST(p.[청구코드] AS varchar(200))))) AS code_norm
  FROM [$(SrcSchema)].[PICMECHM] p
  WHERE (
    TRY_CONVERT(int, p.[보험분류]) IN (9999)
    OR TRY_CONVERT(int, p.[수익분류]) IN (9999)
  )
  AND TRY_CONVERT(int, p.[수가분류]) <> 3
), 
target_codes AS (
  SELECT code_norm FROM hira_measurement_map
  UNION
  SELECT code_norm FROM meas_code_meta
),
op_raw AS (
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
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),'')) IS NOT NULL
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),'')) IS NOT NULL
), 
ip_raw AS (
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
    AND TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),'')) IS NOT NULL
),
claim_union AS (
  SELECT r.*, 'OP' AS src FROM op_raw r JOIN target_codes tc ON tc.code_norm = r.normalized_code
  UNION ALL
  SELECT r.*, 'IP' AS src FROM ip_raw r JOIN target_codes tc ON tc.code_norm = r.normalized_code
),
claim_keys_fanout AS (
  -- Handle 1 code -> N concepts mapping
  SELECT 
    c.PTNTIDNO AS ptntidno,
    REPLACE(c.svc_date, '-', '') AS [date],
    c.src AS [source],
    '' AS mk_lab_id,
    '' AS mk_item_no,
    '' AS mk_lr,
    '' AS mk_seq, -- Empty for claims
    c.serial_no AS mk_serial,
    c.order_no AS mk_order,
    ROW_NUMBER() OVER (
       PARTITION BY c.PTNTIDNO, c.svc_date, c.src, c.serial_no, c.order_no 
       ORDER BY hm.target_concept_id
    ) AS map_index
  FROM claim_union c
  LEFT JOIN hira_measurement_map hm ON hm.code_norm = c.normalized_code
),

-- Combine
all_keys AS (
  SELECT * FROM lab_keys
  UNION ALL
  SELECT * FROM claim_keys_fanout
)

INSERT INTO [$(StagingSchema)].measurement_map (
  ptntidno, [date], [source], mk_lab_id, mk_item_no, mk_lr, mk_seq, mk_serial, mk_order, map_index, measurement_id
)
SELECT 
  k.ptntidno,
  k.[date],
  k.[source],
  k.mk_lab_id,
  k.mk_item_no,
  k.mk_lr,
  k.mk_seq,
  k.mk_serial,
  k.mk_order,
  k.map_index,
  x.base_id + ROW_NUMBER() OVER (ORDER BY k.[date], k.[source], k.mk_order, k.mk_item_no)
FROM all_keys k
CROSS JOIN (
  SELECT ISNULL(MAX(measurement_id), 0) AS base_id FROM [$(StagingSchema)].measurement_map
) x
LEFT JOIN [$(StagingSchema)].measurement_map m
  ON m.ptntidno = k.ptntidno
  AND m.[date] = k.[date]
  AND m.[source] = k.[source]
  AND m.mk_lab_id = k.mk_lab_id
  AND m.mk_item_no = k.mk_item_no
  AND m.mk_lr = k.mk_lr
  AND m.mk_seq = k.mk_seq
  AND m.mk_serial = k.mk_serial
  AND m.mk_order = k.mk_order
  AND m.map_index = k.map_index
WHERE m.ptntidno IS NULL;
