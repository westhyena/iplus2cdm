#!/usr/bin/env Rscript

# -------------------------------------------------------------------------
# Achilles JSON Export Script
# -------------------------------------------------------------------------
# This script exports OHDSI Achilles results to JSON format.
# It reads configuration from environment variables.
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
output_path    <- get_env("ACHILLES_OUTPUT_PATH", "./achilles_results") # Output directory for JSON files

if (is.null(db_password)) {
  stop("Error: POSTGRES_PASSWORD environment variable is not set.")
}

downloadJdbcDrivers("postgresql", pathToDriver = driver_path)

message("-------------------------------------------------------------------------")
message("Starting Achilles JSON Export")
message("-------------------------------------------------------------------------")
message(paste("Server:         ", db_server))
message(paste("CDD Schema:     ", cdm_schema))
message(paste("Results Schema: ", results_schema))
message(paste("Output Path:    ", output_path))
message("-------------------------------------------------------------------------")

# -------------------------------------------------------------------------
# 2. Connection Details
# -------------------------------------------------------------------------
connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = "postgresql",
  server = paste(db_server, db_name, sep = "/"),
  port = db_port,
  user = db_user,
  password = db_password,
  pathToDriver = driver_path
)

# -------------------------------------------------------------------------
# 3. Running Export
# -------------------------------------------------------------------------
# Ensure output directory exists (although exportToJson typically handles it, good practice)
if (!dir.exists(output_path)) {
  dir.create(output_path, recursive = TRUE)
}

tryCatch({
  Achilles::exportToAres(
    connectionDetails = connectionDetails,
    cdmDatabaseSchema = cdm_schema,
    resultsDatabaseSchema = results_schema,
    vocabDatabaseSchema = vocab_path,
    outputPath = output_path,
  )
  message("Achilles export completed successfully!")
}, error = function(e) {
  message("Error during Achilles export:")
  message(e$message)
  quit(status = 1)
})
