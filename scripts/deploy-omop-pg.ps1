param(
    [string]$ConfigPath,
    [switch]$Force,   # Drop schema if exists
    [string]$PsqlBin = "psql"
)

$ErrorActionPreference = 'Stop'

# --- 1. Load Configuration ---
if (-not $ConfigPath) {
    $scriptPath = $MyInvocation.MyCommand.Path
    $root = Split-Path (Split-Path $scriptPath -Parent) -Parent
    $envPath = Join-Path $root ".env"
    if (Test-Path $envPath) { $ConfigPath = $envPath }
}

if ($ConfigPath -and (Test-Path $ConfigPath)) {
    Get-Content $ConfigPath | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()
            # Set variable globally if not set
            if (-not (Get-Variable $k -ErrorAction SilentlyContinue)) {
                New-Variable -Name $k -Value $v -Scope Script -Force
            }
        }
    }
}

# Defaults
if (-not $POSTGRES_SERVER) { $POSTGRES_SERVER = "localhost" }
if (-not $POSTGRES_PORT) { $POSTGRES_PORT = "5432" }
if (-not $POSTGRES_USER) { $POSTGRES_USER = "postgres" }
if (-not $POSTGRES_DB) { $POSTGRES_DB = "TargetDB" } # Default from env.default
if (-not $OMOP_CDM_SCHEMA) { $OMOP_CDM_SCHEMA = "cdm" }

# Set PASSWORD env for psql
if ($POSTGRES_PASSWORD) { $env:PGPASSWORD = $POSTGRES_PASSWORD }

# --- Helper Function ---
function Invoke-Psql {
    param($query, $file)
    
    $args = @("-h", $POSTGRES_SERVER, "-p", $POSTGRES_PORT, "-U", $POSTGRES_USER, "-d", $POSTGRES_DB)
    
    if ($query) {
        $args += @("-c", $query)
        Write-Host "[PSQL] Query: $query"
    } elseif ($file) {
        $args += @("-f", $file)
        Write-Host "[PSQL] Executing file: $file"
    }
    
    & $PsqlBin @args
}

# --- 2. Check Connection & Schema ---
Write-Host "Connecting to PostgreSQL (${POSTGRES_SERVER}:${POSTGRES_PORT}) DB: ${POSTGRES_DB}..." -ForegroundColor Cyan

# Create Schema
if ($Force) {
    Write-Host "Force enabled. Dropping schema $OMOP_CDM_SCHEMA..." -ForegroundColor Yellow
    Invoke-Psql -query "DROP SCHEMA IF EXISTS $OMOP_CDM_SCHEMA CASCADE;"
}

Write-Host "Creating schema $OMOP_CDM_SCHEMA..."
Invoke-Psql -query "CREATE SCHEMA IF NOT EXISTS $OMOP_CDM_SCHEMA;"

# Set search_path for subsequent file executions?
# Psql -f runs in a session. We can prepend "SET search_path TO ..." or rely on DDLs.
# Usually standard DDLs might not include schema qualification or use a placeholder.
# Let's check DDL content. If they use `@cdm_schema`, we need to substitute.
# If they assumes `public`, we need to set search_path.

# Let's inspect DDL files dynamically or assume they adhere to standard OHDSI DDL which usually uses parameters or simple table names.
# If simple table names, we MUST set search path.

# Read DDL files to check for placeholders
$Root = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent
$DDL_DIR = Join-Path $Root "ddl"

$ddlFiles = @(
    "OMOPCDM_postgresql_5.4_ddl.sql",
    "OMOPCDM_postgresql_5.4_primary_keys.sql",
    "OMOPCDM_postgresql_5.4_indices.sql",
    "OMOPCDM_postgresql_5.4_constraints.sql"
)

foreach ($f in $ddlFiles) {
    $path = Join-Path $DDL_DIR $f
    if (Test-Path $path) {
        $content = Get-Content $path -Raw
        
        # Replace @cdmDatabaseSchema with actual schema if present (Standard OHDSI pattern)
        # Also @vocab... but we put everything in one schema usually for simple setup?
        $replaced = $content -replace '@cdmDatabaseSchema', $OMOP_CDM_SCHEMA
        
        # Run
        $tempFile = [IO.Path]::GetTempFileName()
        
        # Prepend search_path just in case DDLs don't use fully qualified names or placeholders
        "SET search_path TO $OMOP_CDM_SCHEMA;" | Out-File $tempFile -Encoding utf8
        $replaced | Out-File $tempFile -Append -Encoding utf8
        
        Invoke-Psql -file $tempFile
        
        Remove-Item $tempFile
    } else {
        Write-Warning "DDL File not found: $path"
    }
}

Write-Host "Deployment completed." -ForegroundColor Green
