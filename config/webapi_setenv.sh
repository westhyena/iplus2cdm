# Java 옵션 추가
export CATALINA_OPTS="$CATALINA_OPTS -Xmx2g"

# 1. WebAPI 메타데이터 DB 설정 (아까 만든 'ohdsi' DB)
export datasource_url="jdbc:postgresql://$POSTGRES_SERVER:$POSTGRES_PORT/$POSTGRES_DB"
export datasource_username=$POSTGRES_USER
export datasource_password=$POSTGRES_PASSWORD
export datasource_driverClassName="org.postgresql.Driver"
export hibernate_dialect="org.hibernate.dialect.PostgreSQLDialect"

# 2. Flyway (DB 자동 스키마 생성 도구) 설정
# WebAPI가 처음 실행될 때 ohdsi DB에 테이블들을 자동으로 만들어줍니다.
export flyway_datasource_url=$datasource_url
export flyway_datasource_username=$datasource_username
export flyway_datasource_password=$datasource_password
export flyway_schemas="ohdsi"
export flyway_placeholders_ohdsiSchema="ohdsi"

# 3. 기타 필수 설정
export security_db_datasource_url=$datasource_url
export security_db_datasource_username=$datasource_username
export security_db_datasource_password=$datasource_password
export spring_batch_repository_tableprefix="ohdsi.BATCH_"
