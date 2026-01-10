# Load env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

echo =========== Results ===========
# 1. WebAPI로부터 SQL 받아오기
# dialect: postgresql, schema: 결과스키마, vocabSchema: 보카스키마
SQL_URL="http://localhost:8080/WebAPI/ddl/results?dialect=postgresql&schema=$OMOP_ACHILLES_RESULTS_SCHEMA&vocabSchema=$OMOP_CDM_SCHEMA&initConceptHierarchy=true"

echo "Fetching DDL from WebAPI..."
curl -s $SQL_URL > init_hierarchy.sql

# 2. psql을 이용해 바로 실행
echo "Executing SQL on PostgreSQL..."

PGPASSWORD=$POSTGRES_PASSWORD psql -h localhost -U $POSTGRES_USER -d $POSTGRES_DB -f init_hierarchy.sql

rm init_hierarchy.sql


echo =========== Achilles ===========
SQL_URL=http://localhost:8080/WebAPI/ddl/achilles?dialect=postgresql&schema=$OMOP_ACHILLES_RESULTS_SCHEMA&vocabSchema=$OMOP_CDM_SCHEMA

echo "Fetching DDL from WebAPI..."
curl -s $SQL_URL > init_concept_count.sql

# 2. psql을 이용해 바로 실행
echo "Executing SQL on PostgreSQL..."

PGPASSWORD=$POSTGRES_PASSWORD psql -h localhost -U $POSTGRES_USER -d $POSTGRES_DB -f init_concept_count.sql

rm init_concept_count.sql

echo "Done! concept_hierarchy table is now created and populated."
