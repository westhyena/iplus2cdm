#!/bin/bash
set -e

# Load environment variables from .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Check for required variables
REQUIRED_VARS=("POSTGRES_SERVER" "POSTGRES_PORT" "POSTGRES_DB" "POSTGRES_USER" "POSTGRES_PASSWORD" "CDM_SOURCE_NAME" "CDM_SOURCE_ABBREVIATION" "OMOP_CDM_SCHEMA" "OMOP_ACHILLES_RESULTS_SCHEMA")

for VAR in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!VAR}" ]; then
    echo "Error: Environment variable $VAR is not set."
    exit 1
  fi
done

echo "Initializing WebAPI source in database..."

# Substitute variables in SQL and execute
envsubst < config/insert_source.sql | PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_SERVER -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB

echo "WebAPI source initialization complete."

sudo systemctl restart tomcat8
