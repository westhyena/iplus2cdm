param(
    [string]$SourceServer,
    [string]$SourceDatabase,
    [string]$SourceUser,
    [string]$SourcePassword,
    [string]$TargetServer,
    [string]$TargetPort = "5432",
    [string]$TargetDatabase,
    [string]$TargetUser,
    [string]$TargetPassword,
    [string]$CdmSchema = "cdm",
    [string]$StagingSchema = "stg_cdm",
    [string]$SrcSchema = "dbo",
    [string]$ConfigPath,
    [string]$BcpBin = "bcp",
    [string]$SqlcmdBin = "sqlcmd",
    [string]$PsqlBin = "psql",
    [switch]$FullReload
)

$ErrorActionPreference = 'Stop'

# Load .env if exists
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
                # Map env vars to params if not passed
                if ($k -eq 'MSSQL_SERVER') { $SourceServer = $v }
                if ($k -eq 'MSSQL_DB') { $SourceDatabase = $v }
                if ($k -eq 'MSSQL_USER') { $SourceUser = $v }
                if ($k -eq 'MSSQL_PASSWORD') { $SourcePassword = $v }
                if ($k -eq 'POSTGRES_SERVER') { $TargetServer = $v }
                if ($k -eq 'POSTGRES_PORT') { $TargetPort = $v }
                if ($k -eq 'POSTGRES_DB') { $TargetDatabase = $v }
                if ($k -eq 'POSTGRES_USER') { $TargetUser = $v }
                if ($k -eq 'POSTGRES_PASSWORD') { $TargetPassword = $v }
                if ($k -eq 'OMOP_CDM_SCHEMA') { $CdmSchema = $v }
                if ($k -eq 'STAGING_SCHEMA') { $StagingSchema = $v }
                if ($k -eq 'SRC_SCHEMA') { $SrcSchema = $v }
            }
        }
    }
}

# Validation
if (-not $SourceServer -or -not $SourceDatabase) { Throw "Source DB info required" }
if (-not $TargetServer -or -not $TargetDatabase) { Throw "Target DB info required using Postgres" }

# Set PGPASSWORD for psql non-interactive
$env:PGPASSWORD = $TargetPassword

# Helper: Run Sqlcmd (MSSQL)
function Invoke-SqlCmdQuery {
    param($query, $vars = @{})
    $args = @("-S", $SourceServer, "-d", $SourceDatabase, "-b", "-I", "-C")
    if ($SourceUser) { $args += @("-U", $SourceUser, "-P", $SourcePassword) }
    else { $args += "-E" }
    
    # Vars
    $vars["CdmSchema"] = $CdmSchema
    $vars["StagingSchema"] = $StagingSchema
    $vars["SrcSchema"] = $SrcSchema
    
    foreach ($k in $vars.Keys) {
        $args += @("-v", "$k=$($vars[$k])")
    }
    
    $args += @("-Q", $query)
    & $SqlcmdBin @args
}

function Invoke-SqlCmdFile {
    param($path, $vars = @{})
    $args = @("-S", $SourceServer, "-d", $SourceDatabase, "-b", "-I", "-C")
    if ($SourceUser) { $args += @("-U", $SourceUser, "-P", $SourcePassword) }
    else { $args += "-E" }
    
    $vars["CdmSchema"] = $CdmSchema
    $vars["StagingSchema"] = $StagingSchema
    $vars["SrcSchema"] = $SrcSchema
    
    foreach ($k in $vars.Keys) {
        $args += @("-v", "$k=$($vars[$k])")
    }
    
    $args += @("-i", $path)
    Write-Host "[SQL] Executing $path"
    & $SqlcmdBin @args
}

# Helper: Get Max ID from Target (Postgres)
function Get-TargetMaxId {
    param($table, $col)
    $q = "SELECT COALESCE(MAX($col), 0) FROM $CdmSchema.$table;"
    $args = @("-h", $TargetServer, "-p", $TargetPort, "-U", $TargetUser, "-d", $TargetDatabase, "-t", "-c", $q)
    $res = & $PsqlBin @args
    return [int]$res.Trim()
}

# Helper: Run BCP Out
function Invoke-BcpOut {
    param($queryFile, $outFile, $vars = @{})
    
    # Read query content to prepare inline query (bcp doesn't take input file directly for queryout easily with var sub? 
    # Actually bcp queryout accepts a query string. We need to read file and substitute vars.)
    # Warning: simple substitution.
    $sql = Get-Content $queryFile -Raw
    $sql = $sql -replace '\$\(CdmSchema\)', $CdmSchema
    $sql = $sql -replace '\$\(StagingSchema\)', $StagingSchema
    $sql = $sql -replace '\$\(SrcSchema\)', $SrcSchema
    if ($vars.MinId) { $sql = $sql -replace '\$\(MinId\)', $vars.MinId }
    else { $sql = $sql -replace '\$\(MinId\)', '0' }
    
    # Handle NewLines for BCP command line (flatten execution)
    # BCP queryout needs "query".
    # We'll save the resolved query to a temp .sql file? No, BCP takes query string.
    # It allows newlines in string? Yes usually.
    
    $args = @($sql, "queryout", $outFile, "-c", "-t`"|`"", "-S", $SourceServer, "-d", $SourceDatabase, "-T") # -T for trusted, change if user/pass
    if ($SourceUser) { 
        $args = @($sql, "queryout", $outFile, "-c", "-t`"|`"", "-S", $SourceServer, "-d", $SourceDatabase, "-U", $SourceUser, "-P", $SourcePassword)
    }
    
    # UTF-8 encoding: bcp -C 65001 requires newer versions. 
    # Windows native text is often CP949? 
    # We will use -w (Standard Unicode UTF-16LE) which is safe, then Postgres handles it (using encoding=UTF16).
    # But wait, -c is char. -w is wide char.
    # Postgres Copy FROM ... ENCODING 'UTF16' works? Yes.
    # Best practice: use -w.
    
    # Override args for -w -> -c (Char/UTF8) to fix encoding issues on Mac/Postgres
    if ($SourceUser) { 
         $args = @($sql, "queryout", $outFile, "-c", "-t|", "-S", $SourceServer, "-d", $SourceDatabase, "-U", $SourceUser, "-P", $SourcePassword, "-u")
    } else {
         $args = @($sql, "queryout", $outFile, "-c", "-t|", "-S", $SourceServer, "-d", $SourceDatabase, "-T", "-u")
    }
    
    Write-Host "[BCP] Exporting ..."
    & $BcpBin @args
}

# Helper: Run Psql Copy
function Invoke-PsqlCopy {
    param($table, $file)
    
    # ... (omitted comments)
    
    $cols = ""
    switch ($table) {
        "person" { $cols = "" } 
        "visit_occurrence" { $cols = "" }
        "observation_period" { $cols = "(observation_period_id, person_id, observation_period_start_date, observation_period_end_date, period_type_concept_id)" }
        "drug_exposure" { $cols = "" }
        "procedure_occurrence" { $cols = "" }
        "device_exposure" { $cols = "" }
        "observation" { $cols = "" }
        "measurement" { $cols = "(measurement_id, person_id, measurement_concept_id, measurement_date, measurement_datetime, measurement_time, measurement_type_concept_id, operator_concept_id, value_as_number, value_as_concept_id, unit_concept_id, range_low, range_high, provider_id, visit_occurrence_id, visit_detail_id, measurement_source_value, measurement_source_concept_id, unit_source_value, unit_source_concept_id, value_source_value, measurement_event_id, meas_event_field_concept_id)" }
        "cost" { $cols = "(cost_id, cost_event_id, cost_domain_id, cost_type_concept_id, currency_concept_id, total_cost, total_charge, total_paid, paid_by_payer, paid_by_patient, paid_patient_copay, paid_patient_coinsurance, paid_patient_deductible, paid_by_primary, paid_ingredient_cost, paid_dispensing_fee, payer_plan_period_id, amount_allowed, revenue_code_concept_id, revenue_code_source_value, drg_concept_id, drg_source_value)" }
    }
    
    # Construct COPY command
    # Use UTF8 encoding as we switched bcp to -c
    # Use FORMAT text to avoid CSV quoting issues (match bcp simple output)
    $copyCmd = "\COPY $CdmSchema.$table $cols FROM '$file' WITH (FORMAT text, DELIMITER '|', ENCODING 'UTF8', NULL '');"
    
    Write-Host "[PSQL] Loading into $table ..."
    & $PsqlBin @("-h", $TargetServer, "-p", $TargetPort, "-U", $TargetUser, "-d", $TargetDatabase, "-c", $copyCmd)
}

# --- Main Execution ---

$Root = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent

# 0. Ensure Staging Schema Exists
Write-Host "Ensuring Staging Schema [$StagingSchema] exists..."
$schemaQuery = "IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = '$StagingSchema') BEGIN EXEC('CREATE SCHEMA [$StagingSchema]') END"
Invoke-SqlCmdQuery -query $schemaQuery

# 1. Map Generation (MSSQL)
if ($FullReload) {
    if ((Get-Command "Invoke-TruncateTables" -ErrorAction SilentlyContinue)) {
         # Defined below but let's just wait until we call it.
    }
}

# 1. Map Generation (MSSQL)
Write-Host "=== Phase 1: Generating Maps on Source ===" -ForegroundColor Cyan

# Load Modules
$hiraModule = Join-Path $Root "scripts/modules/hira-map.ps1"
if (Test-Path $hiraModule) { . $hiraModule }

$measModule = Join-Path $Root "scripts/modules/measurement-map.ps1"
if (Test-Path $measModule) { . $measModule }

# 1.1 Ensure Map Tables Exist (Run DDLs)
$StgDDLs = @(
    "etl-sql/stg/create_person_id_map.sql",
    "etl-sql/stg/create_visit_occurrence_map.sql",
    "etl-sql/stg/create_drug_exposure_map.sql",
    "etl-sql/stg/create_procedure_occurrence_map.sql",
    "etl-sql/stg/create_device_exposure_map.sql",
    "etl-sql/stg/create_observation_map.sql",
    "etl-sql/stg/create_hira_map.sql",  # Dependencies
    "etl-sql/stg/create_drug_vocabulary_map.sql",
    "etl-sql/stg/create_measurement_vocabulary_map.sql",
    "etl-sql/stg/create_measurement_map.sql"
    # Add others if needed
)
foreach ($f in $StgDDLs) {
    Invoke-SqlCmdFile (Join-Path $Root $f)
}

# 1.2 Populate Maps
$MapFiles = @(
    "etl-sql/map/generate_person_map.sql",
    "etl-sql/map/generate_visit_occurrence_map.sql",
    "etl-sql/map/generate_drug_exposure_map.sql",
    "etl-sql/map/generate_procedure_occurrence_map.sql",
    "etl-sql/map/generate_device_exposure_map.sql",
    "etl-sql/map/generate_observation_map.sql",
    "etl-sql/map/generate_measurement_map.sql"
)

foreach ($f in $MapFiles) {
    Invoke-SqlCmdFile (Join-Path $Root $f)
}

# 1.3 Populate Hira/Measurement Maps (PowerShell Modules)
# Construct SqlCmd Args similar to helpers but as a reusable array for modules
$SqlCmdBaseArgs = @("-S", $SourceServer, "-d", $SourceDatabase, "-b", "-I", "-C")
if ($SourceUser) { $SqlCmdBaseArgs += @("-U", $SourceUser, "-P", $SourcePassword) }
else { $SqlCmdBaseArgs += "-E" }
$SqlCmdBaseArgs += @("-v", "StagingSchema=$StagingSchema", "CdmSchema=$CdmSchema", "SrcSchema=$SrcSchema")

$HiraMapPath = Join-Path $Root "vocab/mapping/hira_map.tsv"
$MeasMapPath = Join-Path $Root "vocab/mapping/measurement_map.tsv"

if (Get-Command Invoke-LoadHiraMap -ErrorAction SilentlyContinue) {
    Write-Host "Loading Hira Map from $HiraMapPath ..."
    Invoke-LoadHiraMap -csvPath $HiraMapPath -stagingSchema $StagingSchema -sqlcmd $SqlcmdBin -sqlcmdArgs $SqlCmdBaseArgs -server $SourceServer -database $SourceDatabase -user $SourceUser -password $SourcePassword
}

if (Get-Command Invoke-LoadMeasurementVocabularyMap -ErrorAction SilentlyContinue) {
    Write-Host "Loading Measurement Vocabulary Map from $MeasMapPath ..."
    Invoke-LoadMeasurementVocabularyMap -tsvPath $MeasMapPath -stagingSchema $StagingSchema -sqlcmd $SqlcmdBin -sqlcmdArgs $SqlCmdBaseArgs -server $SourceServer -database $SourceDatabase -user $SourceUser -password $SourcePassword
}


# Helper: Truncate Target Tables (Full Reload)
function Invoke-TruncateTables {
    Write-Host "!!! FULL RELOAD DETECTED !!!" -ForegroundColor Red
    Write-Host "Truncating target tables in schema '$CdmSchema'..." -ForegroundColor Red
    
    # Order matters if no CASCADE, but CASCADE handles dependencies.
    # We will use CASCADE to be safe and simple.
    $tables = @(
        "cost", 
        "observation", 
        "measurement", 
        "device_exposure", 
        "procedure_occurrence", 
        "drug_exposure", 
        "observation_period", 
        "visit_occurrence", 
        "person"
    )
    
    foreach ($t in $tables) {
        $q = "TRUNCATE TABLE $CdmSchema.$t CASCADE;"
        Write-Host "  -> Truncating $t ..."
        $args = @("-h", $TargetServer, "-p", $TargetPort, "-U", $TargetUser, "-d", $TargetDatabase, "-c", $q)
        & $PsqlBin @args
    }
    
    Write-Host "Target tables truncated." -ForegroundColor Yellow
}


# 2. Extract & Load (Bulk)
if ($FullReload) {
    Invoke-TruncateTables
}

Write-Host "=== Phase 2: Bulk Extraction & Loading ===" -ForegroundColor Cyan
$Domains = @(
    @{ Name="person"; Extract="etl-sql/extract/extract_person.sql"; Table="person"; IdCol="person_id" },
    @{ Name="visit_occurrence"; Extract="etl-sql/extract/extract_visit_occurrence.sql"; Table="visit_occurrence"; IdCol="visit_occurrence_id" },
    @{ Name="observation_period"; Extract="etl-sql/extract/extract_observation_period.sql"; Table="observation_period"; IdCol="observation_period_id" }, 
    @{ Name="drug_exposure"; Extract="etl-sql/extract/extract_drug_exposure.sql"; Table="drug_exposure"; IdCol="drug_exposure_id" },
    @{ Name="procedure_occurrence"; Extract="etl-sql/extract/extract_procedure_occurrence.sql"; Table="procedure_occurrence"; IdCol="procedure_occurrence_id" },
    @{ Name="device_exposure"; Extract="etl-sql/extract/extract_device_exposure.sql"; Table="device_exposure"; IdCol="device_exposure_id" },
    @{ Name="measurement"; Extract="etl-sql/extract/extract_measurement.sql"; Table="measurement"; IdCol="measurement_id" }, 
    @{ Name="observation"; Extract="etl-sql/extract/extract_observation.sql"; Table="observation"; IdCol="observation_id" },
    @{ Name="cost"; Extract="etl-sql/extract/extract_cost.sql"; Table="cost"; IdCol="" }
)

foreach ($d in $Domains) {
    Write-Host "Processing $($d.Name)..." -ForegroundColor Yellow
    
    # 2.1 Determine MinId for incremental extract
    $minId = 0
    if ($d.IdCol -ne "") {
        try {
            $max = Get-TargetMaxId $d.Table $d.IdCol
            $minId = $max
            Write-Host "  -> Incremental from ID > $minId"
        } catch {
            Write-Warning "  -> Could not query target max ID. Defaulting to 0."
        }
    }
    
    # 2.2 BCP QueryOut
    $tempFile = [IO.Path]::GetTempFileName()
    try {
        Invoke-BcpOut -queryFile (Join-Path $Root $d.Extract) -outFile $tempFile -vars @{ MinId=$minId }
        
        if ((Get-Item $tempFile).Length -eq 0) {
            Write-Host "  -> No data extracted."
            continue
        }
        
        # 2.3 PSQL Load
        Invoke-PsqlCopy -table $d.Table -file $tempFile
        
    } finally {
        Write-Host "  -> Removing temp file $tempFile"
        if (Test-Path $tempFile) { Remove-Item $tempFile }
    }
}

Write-Host "ETL Complete." -ForegroundColor Green
