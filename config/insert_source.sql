INSERT INTO ohdsi.source (
    source_id,           -- 유니크한 ID (자동 증가가 아니면 수동 기입)
    source_name,         -- ATLAS 화면에 표시될 이름 (예: '정우님 로컬 데이터')
    source_key,          -- 시스템 내부에서 식별자로 쓸 고유 키 (영문/숫자/언더바)
    source_connection,   -- 실제 CDM DB의 JDBC 연결 문자열
    source_dialect       -- DB 종류 (postgresql, sql server, oracle 등)
)
VALUES (
    1, 
    $CDM_SOURCE_NAME,
    $CDM_SOURCE_ABBREVIATION,
    'jdbc:postgresql://$POSTGRES_SERVER:$POSTGRES_PORT/$POSTGRES_DB',
    'postgresql'
);

INSERT INTO ohdsi.source_daimon (source_id, daimon_type, table_qualifier, priority) 
VALUES (1, 0, '$OMOP_CDM_SCHEMA', 1); -- 'public' 스키마에 CDM 데이터가 있는 경우

-- 2. Vocabulary 데이터 위치 지정 (보통 CDM과 같음)
INSERT INTO ohdsi.source_daimon (source_id, daimon_type, table_qualifier, priority) 
VALUES (1, 1, '$OMOP_CDM_SCHEMA', 1);

-- 3. Results 데이터 위치 (쓰기 권한이 있는 스키마여야 함)
INSERT INTO ohdsi.source_daimon (source_id, daimon_type, table_qualifier, priority) 
VALUES (1, 2, '$OMOP_ACHILLES_RESULTS_SCHEMA', 1); -- 'results' 스키마가 별도로 있어야 함

-- 4. Temp 데이터 위치
INSERT INTO ohdsi.source_daimon (source_id, daimon_type, table_qualifier, priority) 
VALUES (1, 5, '$OMOP_ACHILLES_RESULTS_SCHEMA', 1);
