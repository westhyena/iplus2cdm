SET NOCOUNT ON;

-- default param
DECLARE @MinId INT = 0; -- Cost doesn't support MinId easily as it comes from multiple sources. Default 0.

-- 수납/청구 분리 (PAOSUNAB/PAISUNAB 헤더를 슬립 라인에 금액 비례 배분)
-- 급여/비급여 분리 배분: 슬립 [보험분류]='01' 라인이 비급여 (SUNABDET 실측으로 검증됨)
--   비급여 라인: total_charge = w x 비급여액, paid_by_payer = 0,
--               paid_by_patient = total_paid = w x 비급여액 x 수납율
--   급여 라인:   total_charge = w x (청구액 + 급여환자분), paid_by_payer = w x 청구액,
--               total_paid = w x (청구액 + 급여환자분 x 수납율), paid_by_patient = NULL
--   revenue_code_source_value = '비급여'/'급여'
--   w = 라인 금액 / 같은 수납 단위 내 "같은 분류" 라인 금액 합
--   급여환자분 = 수납할금액 - 비급여액, 수납율 = 실수납액 / 수납할금액
--   합계 불변: Σcharge = 청구액+수납할금액, Σpaid = 청구액+실수납액,
--             미수 = Σ(charge-paid) = 수납할금액-실수납액
--   환자 수납 총액(급여 본인부담 포함)은 total_paid - paid_by_payer로 유도 가능
;WITH op_sunab AS (
  -- 외래수납내역 헤더 (환자+수납일자+일련번호 단위)
  SELECT
    p.PTNTIDNO,
    p.[수납일자],
    p.[일련번호],
    SUM(ISNULL(p.[청구액], 0))   AS payer_charge,
    SUM(ISNULL(p.[수납할금액], 0)) AS patient_charge,
    SUM(ISNULL(p.[실수납액], 0))  AS patient_paid,
    SUM(ISNULL(p.[비급여액], 0))  AS nonpay_charge
  FROM [$(SrcSchema)].[PAOSUNAB] p
  WHERE p.PTNTIDNO IS NOT NULL
  GROUP BY p.PTNTIDNO, p.[수납일자], p.[일련번호]
), ip_stay AS (
  -- 입원 건 (진료일자 → 입원건 매핑용 구간)
  SELECT
    h.PTNTIDNO,
    h.INPTADDT,
    MAX(ISNULL(NULLIF(LTRIM(RTRIM(h.INPTDSDT)), ''), '99991231')) AS dis_date
  FROM [$(SrcSchema)].[PMIINPTH] h
  WHERE h.PTNTIDNO IS NOT NULL
  GROUP BY h.PTNTIDNO, h.INPTADDT
), ip_sunab AS (
  -- 입원수납내역 헤더 (입원건 단위, 구간 합산)
  SELECT
    p.PTNTIDNO,
    REPLACE(p.[입원일자], '-', '') AS adm_date,
    SUM(ISNULL(p.[청구액], 0))   AS payer_charge,
    SUM(ISNULL(p.[수납할금액], 0)) AS patient_charge,
    SUM(ISNULL(p.[실수납액], 0))  AS patient_paid,
    SUM(ISNULL(p.[비급여액], 0))  AS nonpay_charge
  FROM [$(SrcSchema)].[PAISUNAB] p
  WHERE p.PTNTIDNO IS NOT NULL
  GROUP BY p.PTNTIDNO, REPLACE(p.[입원일자], '-', '')
), op_lines AS (
  SELECT
    o.PTNTIDNO            AS k_ptntidno,
    REPLACE(o.[진료일자], '-', '') AS k_date,
    'OP'                  AS k_source,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[일련번호])),''))   AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(o.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(o.[금액] AS nvarchar(100)))),'')) AS amount,
    CASE WHEN LTRIM(RTRIM(o.[보험분류])) = '01' THEN 1 ELSE 0 END AS is_nonpay,
    o.[진료일자] AS svc_date_raw
  FROM [$(SrcSchema)].[OCSSLIP] o
  WHERE o.PTNTIDNO IS NOT NULL
), ip_lines AS (
  SELECT
    i.PTNTIDNO            AS k_ptntidno,
    REPLACE(i.[진료일자], '-', '') AS k_date,
    'IP'                  AS k_source,
    0                     AS k_serial_no,
    TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(i.[처방순서])),''))   AS k_order_no,
    TRY_CONVERT(float, NULLIF(LTRIM(RTRIM(CAST(i.[금액] AS nvarchar(100)))),'')) AS amount,
    CASE WHEN LTRIM(RTRIM(i.[보험분류])) = '01' THEN 1 ELSE 0 END AS is_nonpay
  FROM [$(SrcSchema)].[OCSSLIPI] i
  WHERE i.PTNTIDNO IS NOT NULL
), op_alloc AS (
  -- 외래: 같은 수납 단위(환자+일자+일련번호) 내 "같은 급여/비급여 분류" 라인끼리 금액 비례 배분
  SELECT
    l.k_ptntidno, l.k_date, l.k_source, l.k_serial_no, l.k_order_no, l.amount, l.is_nonpay,
    l.amount / NULLIF(SUM(l.amount) OVER (PARTITION BY l.k_ptntidno, l.k_date, l.k_serial_no, l.is_nonpay), 0) AS w,
    s.payer_charge, s.patient_charge, s.patient_paid, s.nonpay_charge
  FROM op_lines l
  LEFT JOIN op_sunab s
    ON s.PTNTIDNO = l.k_ptntidno
   AND s.[수납일자] = l.svc_date_raw
   AND s.[일련번호] = l.k_serial_no
), ip_alloc AS (
  -- 입원: 입원건 내 분류별 금액 비례 배분 (진료일자를 입원 구간으로 매핑)
  SELECT
    l.k_ptntidno, l.k_date, l.k_source, l.k_serial_no, l.k_order_no, l.amount, l.is_nonpay,
    l.amount / NULLIF(SUM(l.amount) OVER (PARTITION BY l.k_ptntidno, st.INPTADDT, l.is_nonpay), 0) AS w,
    s.payer_charge, s.patient_charge, s.patient_paid, s.nonpay_charge
  FROM ip_lines l
  OUTER APPLY (
    SELECT TOP 1 t.INPTADDT
    FROM ip_stay t
    WHERE t.PTNTIDNO = l.k_ptntidno
      AND l.k_date BETWEEN t.INPTADDT AND t.dis_date
    ORDER BY t.INPTADDT DESC
  ) st
  LEFT JOIN ip_sunab s
    ON s.PTNTIDNO = l.k_ptntidno
   AND s.adm_date = st.INPTADDT
), slip_costs AS (
  SELECT
    a.k_ptntidno, a.k_date, a.k_source, a.k_serial_no, a.k_order_no, a.amount,
    CASE WHEN a.is_nonpay = 1 THEN N'비급여' ELSE N'급여' END AS rev_label,
    ROUND(CASE WHEN a.is_nonpay = 1
               THEN a.w * a.nonpay_charge
               ELSE a.w * (a.payer_charge + a.patient_charge - a.nonpay_charge) END, 0) AS total_charge,
    ROUND(CASE WHEN a.is_nonpay = 1
               THEN a.w * a.nonpay_charge * a.pay_ratio
               ELSE a.w * (a.payer_charge + (a.patient_charge - a.nonpay_charge) * a.pay_ratio) END, 0) AS total_paid,
    CASE WHEN a.is_nonpay = 1 THEN 0
         ELSE ROUND(a.w * a.payer_charge, 0) END AS paid_by_payer,
    CASE WHEN a.is_nonpay = 1 THEN ROUND(a.w * a.nonpay_charge * a.pay_ratio, 0)
         ELSE NULL END AS paid_by_patient
  FROM (
    SELECT u.*,
           CASE WHEN ISNULL(u.patient_charge, 0) = 0 THEN 1
                ELSE u.patient_paid / u.patient_charge END AS pay_ratio
    FROM (
      SELECT * FROM op_alloc
      UNION ALL
      SELECT * FROM ip_alloc
    ) u
  ) a
), raw_data AS (
-- 1. Procedure Costs
  SELECT
    km.procedure_occurrence_id AS cost_event_id,
    'Procedure' AS cost_domain_id,
    32817       AS cost_type_concept_id,
    44818598    AS currency_concept_id, -- KRW
    u.amount    AS total_cost,
    u.total_charge,
    u.total_paid,
    u.paid_by_payer,
    u.paid_by_patient,
    NULL AS paid_patient_copay,
    NULL AS paid_patient_coinsurance,
    NULL AS paid_patient_deductible,
    NULL AS paid_by_primary,
    NULL AS paid_ingredient_cost,
    NULL AS paid_dispensing_fee,
    NULL AS payer_plan_period_id,
    NULL AS amount_allowed,
    NULL AS revenue_code_concept_id,
    u.rev_label AS revenue_code_source_value,
    NULL AS drg_concept_id,
    NULL AS drg_source_value
  FROM slip_costs u
  JOIN [$(StagingSchema)].procedure_occurrence_map km
    ON km.ptntidno = u.k_ptntidno
   AND km.[date]   = u.k_date
   AND km.[source] = u.k_source
   AND km.serial_no = u.k_serial_no
   AND km.order_no  = u.k_order_no
   AND km.map_index = 1
  WHERE u.amount IS NOT NULL AND u.amount <> 0

  UNION ALL

  -- 2. Drug Costs
  SELECT
    km.drug_exposure_id AS cost_event_id,
    'Drug' AS cost_domain_id,
    32817  AS cost_type_concept_id,
    44818598 AS currency_concept_id,
    u.amount AS total_cost,
    u.total_charge, u.total_paid, u.paid_by_payer, u.paid_by_patient,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, u.rev_label, NULL, NULL
  FROM slip_costs u
  JOIN [$(StagingSchema)].drug_exposure_map km
    ON km.ptntidno = u.k_ptntidno
   AND km.[date]   = u.k_date
   AND km.[source] = u.k_source
   AND km.serial_no = u.k_serial_no
   AND km.order_no  = u.k_order_no
   AND km.map_index = 1
  WHERE u.amount IS NOT NULL AND u.amount <> 0

  UNION ALL

  -- 3. Device Costs
  SELECT
    km.device_exposure_id AS cost_event_id,
    'Device' AS cost_domain_id,
    32817    AS cost_type_concept_id,
    44818598 AS currency_concept_id,
    u.amount AS total_cost,
    u.total_charge, u.total_paid, u.paid_by_payer, u.paid_by_patient,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, u.rev_label, NULL, NULL
  FROM slip_costs u
  JOIN [$(StagingSchema)].device_exposure_map km
    ON km.ptntidno = u.k_ptntidno
   AND km.[date]   = u.k_date
   AND km.[source] = u.k_source
   AND km.serial_no = u.k_serial_no
   AND km.order_no  = u.k_order_no
   AND km.map_index = 1
  WHERE u.amount IS NOT NULL AND u.amount <> 0

  UNION ALL

  -- 4. Observation Costs
  SELECT
    km.observation_id AS cost_event_id,
    'Observation' AS cost_domain_id,
    32817         AS cost_type_concept_id,
    44818598      AS currency_concept_id,
    u.amount      AS total_cost,
    u.total_charge, u.total_paid, u.paid_by_payer, u.paid_by_patient,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, u.rev_label, NULL, NULL
  FROM slip_costs u
  JOIN [$(StagingSchema)].observation_map km
    ON km.ptntidno = u.k_ptntidno
   AND km.[date]   = u.k_date
   AND km.[source] = u.k_source
   AND km.serial_no = u.k_serial_no
   AND km.order_no  = u.k_order_no
   AND km.map_index = 1
  WHERE u.amount IS NOT NULL AND u.amount <> 0

  UNION ALL

  -- 5. Measurement Costs (청구코드 소스만 — LAB(INFLABD) 검사는 슬립 금액이 없음)
  SELECT
    km.measurement_id AS cost_event_id,
    'Measurement' AS cost_domain_id,
    32817         AS cost_type_concept_id,
    44818598      AS currency_concept_id,
    u.amount      AS total_cost,
    u.total_charge, u.total_paid, u.paid_by_payer, u.paid_by_patient,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, u.rev_label, NULL, NULL
  FROM slip_costs u
  JOIN [$(StagingSchema)].measurement_map km
    ON km.ptntidno = u.k_ptntidno
   AND km.[date]   = u.k_date
   AND km.[source] = u.k_source
   AND km.mk_lab_id = ''
   AND km.mk_item_no = ''
   AND km.mk_lr = ''
   AND km.mk_seq = ''
   AND km.mk_serial = u.k_serial_no
   AND km.mk_order  = u.k_order_no
   AND km.map_index = 1
  WHERE u.amount IS NOT NULL AND u.amount <> 0
)
SELECT
  ROW_NUMBER() OVER (ORDER BY cost_domain_id, cost_event_id) AS cost_id,
  cost_event_id,
  cost_domain_id,
  cost_type_concept_id,
  currency_concept_id,
  total_cost,
  total_charge,
  total_paid,
  paid_by_payer,
  paid_by_patient,
  paid_patient_copay,
  paid_patient_coinsurance,
  paid_patient_deductible,
  paid_by_primary,
  paid_ingredient_cost,
  paid_dispensing_fee,
  payer_plan_period_id,
  amount_allowed,
  revenue_code_concept_id,
  revenue_code_source_value,
  drg_concept_id,
  drg_source_value
FROM raw_data;
