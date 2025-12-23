param(
    [string]$ConfigPath,
    [string]$VocabDir,
    [string]$VocabPath, # Legacy support
    [string]$PsqlBin = "psql",
    [switch]$Force
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
if (-not $POSTGRES_DB) { $POSTGRES_DB = "TargetDB" }
if (-not $OMOP_CDM_SCHEMA) { $OMOP_CDM_SCHEMA = "cdm" }
if ($POSTGRES_PASSWORD) { $env:PGPASSWORD = $POSTGRES_PASSWORD }

$Root = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent

# --- 2. Extract Logic ---
if (-not $VocabDir) {
    if ($VocabPath -and (Test-Path $VocabPath -PathType Container)) {
        $VocabDir = $VocabPath
    } else {
        Write-Host "Usage: ./load-vocab-pg.ps1 -VocabDir ./vocab/extracted -Force" -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path $VocabDir)) {
    Write-Host "Directory not found: $VocabDir" -ForegroundColor Red
    exit 1
}

Write-Host "Using Vocabulary Directory: $VocabDir"

# --- 3. Helper Functions ---
function Invoke-Psql {
    param($query, $file, $msg)
    
    $args = @("-h", $POSTGRES_SERVER, "-p", $POSTGRES_PORT, "-U", $POSTGRES_USER, "-d", $POSTGRES_DB)
    
    if ($msg) { Write-Host $msg -ForegroundColor Green }
    
    if ($query) {
        $args += @("-c", $query)
    } elseif ($file) {
        $args += @("-f", $file)
    }
    
    & $PsqlBin @args
}

function Drop-ForeignKeys {
    Write-Host "Dropping Foreign Keys in schema '$OMOP_CDM_SCHEMA'..." -ForegroundColor Yellow
    # Generate DROP CONSTRAINT statements dynamically
    # Use TEMP FILE to avoid shell escaping issues with DO $$ ... $$
    $sql = @"
DO `$`$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT table_name, constraint_name 
              FROM information_schema.table_constraints 
              WHERE constraint_schema = '$OMOP_CDM_SCHEMA' AND constraint_type = 'FOREIGN KEY') 
    LOOP
        EXECUTE 'ALTER TABLE ' || quote_ident('$OMOP_CDM_SCHEMA') || '.' || quote_ident(r.table_name) || ' DROP CONSTRAINT ' || quote_ident(r.constraint_name) || ';';
    END LOOP;
END `$`$;
"@
    $tempFile = [IO.Path]::GetTempFileName()
    try {
        $sql | Out-File $tempFile -Encoding utf8
        Invoke-Psql -file $tempFile
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile }
    }
}

function Restore-Constraints {
    Write-Host "Restoring Constraints from DDL..." -ForegroundColor Cyan
    $constraintFile = Join-Path $Root "ddl/OMOPCDM_postgresql_5.4_constraints.sql"
    
    if (Test-Path $constraintFile) {
        # Need to handle @cdmDatabaseSchema replacement
        $content = Get-Content $constraintFile -Raw
        $replaced = $content -replace '@cdmDatabaseSchema', $OMOP_CDM_SCHEMA
        $tempFile = [IO.Path]::GetTempFileName()
        try {
            "SET search_path TO $OMOP_CDM_SCHEMA;" | Out-File $tempFile -Encoding utf8
            $replaced | Out-File $tempFile -Append -Encoding utf8
            Invoke-Psql -file $tempFile -msg "Executing Constraints DDL"
        } finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile }
        }
    } else {
        Write-Warning "Constraints DDL file not found: $constraintFile"
    }
}

function Invoke-Copy {
    param($table, $file)
    
    $header = Get-Content -LiteralPath $file -TotalCount 1
    $isTsv = $file.ToLower().EndsWith(".tsv") -or ($header -match "`t")
    
    $delim = if ($isTsv) { "`t" } else { "," }
    $fullTable = "$OMOP_CDM_SCHEMA.$table"
    
    # Header format
    $qDelim = if ($delim -eq "`t") { "E'\t'" } else { "','" }
    $copyOpts = "FORMAT csv, HEADER, DELIMITER $qDelim, QUOTE E'\b', NULL ''"
    if ($delim -eq ",") {
        $copyOpts = "FORMAT csv, HEADER, DELIMITER ',', NULL ''"
    }
    
    $cmd = "\COPY $fullTable FROM '$file' WITH ($copyOpts);"
    
    Write-Host "Loading $table ..."
    $res = & $PsqlBin -h $POSTGRES_SERVER -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c $cmd 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to load $table. Output: $res"
    } else {
        Write-Host "  -> Done."
    }
}

# --- 4. Main Execution ---

# A. Drop Constraints (to resolve Circular Dependency)
if ($Force) {
    Drop-ForeignKeys
    
    # Truncate Tables
    # Note: Just truncate the ones we load, or all? User list.
    $OrderedTables = @('CONCEPT','VOCABULARY','DOMAIN','CONCEPT_CLASS','RELATIONSHIP','CONCEPT_SYNONYM','CONCEPT_RELATIONSHIP','DRUG_STRENGTH','CONCEPT_ANCESTOR')
    
    foreach ($t in $OrderedTables) {
         Invoke-Psql -query "TRUNCATE TABLE $OMOP_CDM_SCHEMA.$t CASCADE;"
    }
}

# B. Load Data
$OrderedTables = @('CONCEPT','VOCABULARY','DOMAIN','CONCEPT_CLASS','RELATIONSHIP','CONCEPT_SYNONYM','CONCEPT_RELATIONSHIP','DRUG_STRENGTH','CONCEPT_ANCESTOR')

foreach ($t in $OrderedTables) {
    $f = Get-ChildItem $VocabDir | Where-Object { $_.Name -match "^$t\.(csv|tsv)$" } | Select-Object -First 1
    if ($f) {
        Invoke-Copy -table $t -file $f.FullName
    } else {
        Write-Warning "File for table $t not found."
    }
}

# C. Restore Constraints
if ($Force) {
    Restore-Constraints
}

Write-Host "Vocabulary Load Complete." -ForegroundColor Green
