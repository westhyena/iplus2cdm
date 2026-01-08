# Load env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# 1. WebAPI로부터 SQL 받아오기
# dialect: postgresql, schema: 결과스키마, vocabSchema: 보카스키마
SQL_URL="http://localhost:8080/WebAPI/ddl/results?dialect=postgresql&schema=achilles&vocabSchema=public&initConceptHierarchy=true"

echo "Fetching DDL from WebAPI..."
curl -s $SQL_URL > init_hierarchy.sql

# 2. psql을 이용해 바로 실행
echo "Executing SQL on PostgreSQL..."

psql -h localhost -U $POSTGRES_USER -d $POSTGRES_DB -f init_hierarchy.sql

rm init_hierarchy.sql

echo "Done! concept_hierarchy table is now created and populated."
