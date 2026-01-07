#!/usr/bin/env Rscript

# -------------------------------------------------------------------------
# Achilles Execution Script
# -------------------------------------------------------------------------
# This script executes OHDSI Achilles on a PostgreSQL CDM database.
# It reads configuration from environment variables.
#
# Usage:
#   Rscript bin/run_achilles.R
# -------------------------------------------------------------------------

# Install/Load necessary packages
if (!require("DatabaseConnector")) install.packages("DatabaseConnector")
if (!require("Achilles")) install.packages("Achilles")

library(DatabaseConnector)
library(Achilles)
library(ParallelLogger)

# -------------------------------------------------------------------------
# 1. Read Environment Variables
# -------------------------------------------------------------------------
# Function to get env var with default
get_env <- function(key, default = NULL) {
  val <- Sys.getenv(key)
  if (val == "") return(default)
  return(val)
}

driver_path <- get_env("DRIVER_PATH", "./jdbc")
db_server   <- get_env("POSTGRES_SERVER", "localhost")
db_port     <- get_env("POSTGRES_PORT", "5432")
db_name     <- get_env("POSTGRES_DB", "TargetDB")
db_user     <- get_env("POSTGRES_USER", "postgres")
db_password <- get_env("POSTGRES_PASSWORD")
cdm_schema  <- get_env("OMOP_CDM_SCHEMA", "cdm")
# Default results schema to 'results' or 'achilles' if not specified
results_schema <- get_env("OMOP_ACHILLES_RESULTS_SCHEMA", "achilles")
vocab_schema   <- get_env("OMOP_VOCAB_SCHEMA", cdm_schema) # Default to CDM schema if not separate

if (is.null(db_password)) {
  stop("Error: POSTGRES_PASSWORD environment variable is not set.")
}

downloadJdbcDrivers("postgresql", pathToDriver = driver_path)

message("-------------------------------------------------------------------------")
message("Starting Achilles Execution")
message("-------------------------------------------------------------------------")
message(paste("Server:       ", db_server))
message(paste("Port:         ", db_port))
message(paste("Database:     ", db_name))
message(paste("User:         ", db_user))
message(paste("CDM Schema:   ", cdm_schema))
message(paste("Vocab Schema: ", vocab_schema))
message(paste("Results Schema:", results_schema))
message("-------------------------------------------------------------------------")

# -------------------------------------------------------------------------
# 2. Test Connection
# -------------------------------------------------------------------------
connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = "postgresql",
  server = paste(db_server, db_name, sep = "/"),
  port = db_port,
  user = db_user,
  password = db_password,
  pathToDriver = driver_path
)

tryCatch({
  conn <- DatabaseConnector::connect(connectionDetails)
  message("Successfully connected to the database!")
  DatabaseConnector::disconnect(conn)
}, error = function(e) {
  stop(paste("Failed to connect to database:", e$message))
})

# -------------------------------------------------------------------------
# 3. Create Results Schema (if not exists)
# -------------------------------------------------------------------------
# Achilles might create tables, but basic schema should exist.
# We can try to create it using raw SQL if needed, but usually this is done by DBA.
# Here we'll rely on user setup or assume it exists/is creatable.
# Note: DatabaseConnector can execute SQL to create schema.

# -------------------------------------------------------------------------
# 4. Run Achilles
# -------------------------------------------------------------------------
# Configurable parameters (could be extended to env vars)
num_threads <- as.numeric(get_env("ACHILLES_NUM_THREADS", "1"))
source_name <- get_env("OMOP_CDM_SCHEMA", "cdm")
cdm_version <- get_env("CDM_VERSION", "5.4")

message(paste("Running Achilles with", num_threads, "threads..."))

tryCatch({
  Achilles::achilles(
    connectionDetails = connectionDetails,
    cdmDatabaseSchema = cdm_schema,
    resultsDatabaseSchema = results_schema,
    vocabDatabaseSchema = vocab_schema,
    sourceName = source_name,
    cdmVersion = cdm_version,
    numThreads = num_threads,
    createTable = TRUE,
    runHeel = TRUE,
    runCostAnalysis = TRUE,
    smallCellCount = 5
  )

  Achilles::addConceptHierarchy(
    connectionDetails = connectionDetails,
    resultsDatabaseSchema = results_schema,
    vocabDatabaseSchema = vocab_schema
  )

  Achilles::createIndices(
    connectionDetails = connectionDetails,
    resultsDatabaseSchema = results_schema
  )
  message("Achilles execution completed successfully!")
}, error = function(e) {
  message("Error during Achilles execution:")
  message(e$message)
  quit(status = 1)
})
