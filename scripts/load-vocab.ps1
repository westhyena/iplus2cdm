param(
  [string]$Server,
  [string]$Database,
  [string]$User,
  [string]$Password,
  [string]$CdmSchema,
  [string]$ConfigPath,
  [switch]$UseEnv,
  [switch]$PromptPassword,
  [string]$VocabExtractDir,
  [string]$VocabCsvDelim,
  [string]$SqlcmdBin,
  [string]$BcpBin,
  [int]$VocabBcpBatchSize,
  [int]$BcpCodePage,
  [bool]$VocabDeleteBeforeLoad,
  [string]$StagingSchema,
  [bool]$StagingTruncateBeforeLoad
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  return (Split-Path -Parent $scriptRoot)
}

# Defaults
$defaults = @{
  Server                 = "localhost"
  Database               = "MyDB"
  User                   = ""
  Password               = ""
  CdmSchema              = "cdm"
  VocabExtractDir        = Join-Path (Get-RepoRoot) "vocab/extracted"
  VocabCsvDelim          = ","
  VocabDeleteBeforeLoad  = $false
  SqlcmdBin              = "sqlcmd"
  BcpBin                 = "bcp"
  VocabBcpBatchSize      = 50000
  BcpCodePage            = 65001
  StagingSchema          = "stg_cdm"
  StagingTruncateBeforeLoad = $true
}

# Auto .env
if (-not $ConfigPath) {
  $root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $defaultEnvScriptDir = Join-Path $root ".env"
  $defaultEnvRepoRoot  = Join-Path (Split-Path -Parent $root) ".env"
  if (Test-Path $defaultEnvScriptDir) { $ConfigPath = $defaultEnvScriptDir }
  elseif (Test-Path $defaultEnvRepoRoot) { $ConfigPath = $defaultEnvRepoRoot }
}

# Load .env
$config = @{}
if ($ConfigPath) {
  if (!(Test-Path $ConfigPath)) { throw "Config file not found: $ConfigPath" }
  $ext = [IO.Path]::GetExtension($ConfigPath).ToLowerInvariant()
  if ($ext -ne ".env") { throw "Unsupported config extension: $ext (use .env)" }
  $raw = Get-Content $ConfigPath
  $kvMap = @{}
  foreach ($line in $raw) {
    if ($line -match '^(\s*#|\s*$)') { continue }
    $kv = $line -split '=',2
    if ($kv.Count -eq 2) { $kvMap[$kv[0].Trim()] = $kv[1].Trim() }
  }
  $map = @{
    OMOP_SERVER            = "Server"
    OMOP_DB                = "Database"
    OMOP_USER              = "User"
    OMOP_PASSWORD          = "Password"
    OMOP_CDM_SCHEMA        = "CdmSchema"
    VOCAB_EXTRACT_DIR      = "VocabExtractDir"
    VOCAB_CSV_DELIM        = "VocabCsvDelim"
    VOCAB_DELETE_BEFORE_LOAD = "VocabDeleteBeforeLoad"
    SQLCMD_BIN             = "SqlcmdBin"
    BCP_BIN                = "BcpBin"
    VOCAB_BCP_BATCH_SIZE   = "VocabBcpBatchSize"
    STAGING_SCHEMA         = "StagingSchema"
  }
  foreach ($k in $kvMap.Keys) { if ($map.ContainsKey($k)) { $config[$map[$k]] = $kvMap[$k] } }
}

# Merge
$cfg = $defaults.Clone()
foreach ($k in $config.Keys) { if ($config[$k]) { $cfg[$k] = $config[$k] } }
if ($UseEnv) {
  $envMap = @{
    Server                = $env:OMOP_SERVER
    Database              = $env:OMOP_DB
    User                  = $env:OMOP_USER
    Password              = $env:OMOP_PASSWORD
    CdmSchema             = $env:OMOP_CDM_SCHEMA
    VocabExtractDir       = $env:VOCAB_EXTRACT_DIR
    VocabCsvDelim         = $env:VOCAB_CSV_DELIM
    VocabDeleteBeforeLoad = $env:VOCAB_DELETE_BEFORE_LOAD
    SqlcmdBin             = $env:SQLCMD_BIN
    BcpBin                = $env:BCP_BIN
    VocabBcpBatchSize     = $env:VOCAB_BCP_BATCH_SIZE
    StagingSchema         = $env:STAGING_SCHEMA
  }
  foreach ($k in $envMap.Keys) { if ($envMap[$k]) { $cfg[$k] = $envMap[$k] } }
}
foreach ($name in $PSBoundParameters.Keys) { if ($name -in $cfg.Keys) { $cfg[$name] = $PSBoundParameters[$name] } }

# Coercions
if ($cfg.VocabDeleteBeforeLoad -is [string]) { $cfg.VocabDeleteBeforeLoad = [System.Convert]::ToBoolean($cfg.VocabDeleteBeforeLoad) }
if ($cfg.StagingTruncateBeforeLoad -is [string]) { $cfg.StagingTruncateBeforeLoad = [System.Convert]::ToBoolean($cfg.StagingTruncateBeforeLoad) }
if ($cfg.VocabBcpBatchSize -is [string]) { $cfg.VocabBcpBatchSize = [int]$cfg.VocabBcpBatchSize }
if ($cfg.BcpCodePage -is [string]) { $cfg.BcpCodePage = [int]$cfg.BcpCodePage }

# Prompt password
if (-not $cfg.Password -and $cfg.User -and $PromptPassword) {
  $secure = Read-Host -AsSecureString "Enter password for user '$($cfg.User)'"
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $cfg.Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

# Tools
function Require-Command($name) { if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Required command not found: $name" } }
Require-Command $cfg.SqlcmdBin
Require-Command $cfg.BcpBin

# Helpers
function Test-HasVocabFiles([string]$dir) {
  $names = @('CONCEPT','VOCABULARY','DOMAIN','CONCEPT_CLASS')
  foreach ($n in $names) {
    $possible = @(
      (Join-Path $dir "$n.csv"), (Join-Path $dir "$n.CSV"),
      (Join-Path $dir "$n.tsv"), (Join-Path $dir "$n.TSV"),
      (Join-Path $dir "$($n.ToLower()).csv"), (Join-Path $dir "$($n.ToLower()).tsv")
    )
    foreach ($p in $possible) { if (Test-Path $p) { return $true } }
  }
  return $false
}

function Find-VocabDir([string]$extractDir) {
  $candidates = @($extractDir)
  $child = Get-ChildItem -Path $extractDir -Directory -ErrorAction SilentlyContinue
  if ($child) { $candidates += $child.FullName }
  foreach ($d in $candidates) { if (Test-HasVocabFiles $d) { return $d } }
  throw "vocabulary CSV/TSV 파일을 찾을 수 없습니다. (확인 경로: $extractDir)"
}

function Get-TableFile([string]$dir,[string]$table) {
  $cand = @(
    (Join-Path $dir "$table.csv"), (Join-Path $dir "$table.CSV"),
    (Join-Path $dir "$table.tsv"), (Join-Path $dir "$table.TSV"),
    (Join-Path $dir "$(($table).ToLower()).csv"), (Join-Path $dir "$(($table).ToLower()).tsv"),
    (Join-Path $dir "$table.txt"), (Join-Path $dir "$table.TXT")
  )
  foreach ($p in $cand) { if (Test-Path $p) { return $p } }
  $regex = "^" + [Regex]::Escape($table) + "\.(csv|tsv|txt)$"
  $loose = Get-ChildItem -Path $dir -File | Where-Object { $_.Name -match $regex } | Select-Object -First 1
  if ($loose) { return $loose.FullName }
  return $null
}

function Detect-Delimiter([string]$filePath, [string]$default) {
  try {
    $line = Get-Content -LiteralPath $filePath -TotalCount 1
    if ($null -ne $line) {
      $tabCount = ($line -split "`t").Length
      $commaCount = ($line -split ",").Length
      if ($tabCount -gt $commaCount) { return "`t" }
      if ($commaCount -gt $tabCount) { return "," }
    }
  } catch {}
  return $default
}

function DetectRowTerminator([string]$filePath) {
  try {
    $fs = [System.IO.File]::OpenRead($filePath)
    try {
      $buf = New-Object byte[] 1048576
      $n = $fs.Read($buf, 0, $buf.Length)
      for ($i = 0; $i -lt ($n - 1); $i++) {
        if ($buf[$i] -eq 13 -and $buf[$i+1] -eq 10) { return '0x0d0a' }
      }
      for ($i = 0; $i -lt $n; $i++) { if ($buf[$i] -eq 10) { return '0x0a' } }
    } finally { $fs.Close() }
  } catch {}
  return '0x0a'
}

function Build-SqlcmdArgs() {
  $args = @('-S', $cfg.Server, '-d', $cfg.Database, '-b', '-V', '16')
  if ($cfg.User) {
    if (-not $cfg.Password) { throw "Password is required when User is set (or use -PromptPassword)" }
    $args += @('-U', $cfg.User, '-P', $cfg.Password)
  } else { $args += @('-E') }
  return ,$args
}

# Preflight connection test
$sqlcmdArgs = Build-SqlcmdArgs
try { & $cfg.SqlcmdBin @sqlcmdArgs -Q "SELECT 1" | Out-Null }
catch { throw "DB 연결 실패입니다. OMOP_SERVER/OMOP_USER/OMOP_PASSWORD, 포트(예: 'host,1433') 설정을 확인하세요. 오류: $($_.Exception.Message)" }

# Ensure dirs
$null = New-Item -ItemType Directory -Force -Path $cfg.VocabExtractDir | Out-Null
$vocabDir = Find-VocabDir -extractDir $cfg.VocabExtractDir
Write-Host "[OK] vocabulary 디렉터리: $vocabDir"

 

# Create staging schema
$createSchema = "IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = '$($cfg.StagingSchema)') EXEC('CREATE SCHEMA [$($cfg.StagingSchema)]');"
& $cfg.SqlcmdBin @sqlcmdArgs -Q $createSchema | Out-Null

# Pre-clear ALL staging tables regardless of file presence (per-table, TRY/CATCH)
$preTruncateTables = @('CONCEPT','VOCABULARY','DOMAIN','CONCEPT_CLASS','RELATIONSHIP','CONCEPT_SYNONYM','CONCEPT_RELATIONSHIP','DRUG_STRENGTH','CONCEPT_ANCESTOR')
foreach ($t in $preTruncateTables) {
  $objName = "$($cfg.StagingSchema).$t"          # schema.table (unbracketed) for OBJECT_ID
  $qualified = "[$($cfg.StagingSchema)].[$t]"     # bracketed for DDL/DML
  $sql = @"
IF OBJECT_ID('$objName','U') IS NOT NULL
BEGIN TRY
  TRUNCATE TABLE $qualified;
END TRY
BEGIN CATCH
  DELETE FROM $qualified;
END CATCH
"@
  & $cfg.SqlcmdBin @sqlcmdArgs -Q $sql | Out-Null
}
Write-Host "[OK] Staging 초기화 완료: $($cfg.StagingSchema)"

function QuoteIdent([string]$name) { return "[" + ($name -replace "]","]]") + "]" }

function Ensure-Staging-Table([string]$table, [string]$filePath) {
  $delim = Detect-Delimiter -filePath $filePath -default $cfg.VocabCsvDelim
  $header = Get-Content -LiteralPath $filePath -TotalCount 1
  if (-not $header) { throw "헤더를 읽지 못했습니다: $filePath" }
  $cols = $header -split $delim, [System.StringSplitOptions]::None | ForEach-Object { $_ -replace "\r$","" }
  $cols = $cols | ForEach-Object { $_.Trim() }
  if ($cols.Count -eq 0) { throw "헤더 컬럼이 없습니다: $filePath" }
  $colsQuoted = $cols | ForEach-Object { QuoteIdent $_ }
  $colsDef = ($colsQuoted | ForEach-Object { "$_ NVARCHAR(4000) NULL" }) -join ","
  $full = "[$($cfg.StagingSchema)]." + (QuoteIdent $table)
  $objForObjectId = "$($cfg.StagingSchema).$table"  # OBJECT_ID용 언브래킷 식별자

  # CREATE TABLE IF NOT EXISTS
  $sqlCreate = @"
IF OBJECT_ID('$objForObjectId','U') IS NULL
BEGIN
  CREATE TABLE $full ($colsDef);
END
"@
  & $cfg.SqlcmdBin @sqlcmdArgs -Q $sqlCreate | Out-Null

  # Always clear staging table before load (TRUNCATE with DELETE fallback)
  $sqlClear = @"
IF OBJECT_ID('$objForObjectId','U') IS NOT NULL
BEGIN TRY
  TRUNCATE TABLE $full;
END TRY
BEGIN CATCH
  DELETE FROM $full;
END CATCH
"@
  & $cfg.SqlcmdBin @sqlcmdArgs -Q $sqlClear | Out-Null
}

function Build-BcpAuthArgs() {
  $args = @('-S', $cfg.Server, '-d', $cfg.Database)
  if ($cfg.User) { $args += @('-U', $cfg.User, '-P', $cfg.Password) } else { $args += @('-T') }
  return ,$args
}

function Bcp-Into-Staging([string]$table, [string]$filePath) {
  Ensure-Staging-Table -table $table -filePath $filePath
  $detected = Detect-Delimiter -filePath $filePath -default $cfg.VocabCsvDelim
  $isTsv = ($detected -eq "`t") -or $filePath.ToLower().EndsWith('.tsv')
  $tOpt = if ($isTsv) { "-t0x09" } else { "-t$($cfg.VocabCsvDelim)" }
  $rowHex = DetectRowTerminator -filePath $filePath
  $rOpt = "-r$rowHex"
  $qualified = "[$($cfg.StagingSchema)]." + (QuoteIdent $table)
  $errDir = Join-Path (Get-RepoRoot) "vocab/bcp-errors"
  $null = New-Item -ItemType Directory -Force -Path $errDir | Out-Null
  $errFile = Join-Path $errDir ("$table.err")

  $bcpAuthArgs = Build-BcpAuthArgs
  Write-Host "[INFO] STAGING BCP: $filePath -> $qualified (server=$($cfg.Server), db=$($cfg.Database), field=$tOpt, row=$rOpt, batch=$($cfg.VocabBcpBatchSize))"
  $extra = @('-c', $tOpt, $rOpt, '-F', '2', '-b', $cfg.VocabBcpBatchSize.ToString(), '-k', '-e', $errFile)
  if ($cfg.BcpCodePage) { $extra += @('-C', $cfg.BcpCodePage.ToString()) }
  & $cfg.BcpBin $qualified in "$filePath" @bcpAuthArgs @extra
  Write-Host "실행 커맨드 : $($cfg.BcpBin) $qualified in $filePath $($bcpAuthArgs -join ' ') $($extra -join ' ') "
  if ($LASTEXITCODE -ne 0) { throw "BCP 실패 (exit=$LASTEXITCODE): $table (error file: $errFile)" }
  Write-Host "[OK] STAGED: $table"
}

# Load order: 파일 존재 기준으로 순회
$tables = @('CONCEPT','VOCABULARY','DOMAIN','CONCEPT_CLASS','RELATIONSHIP','CONCEPT_SYNONYM','CONCEPT_RELATIONSHIP','DRUG_STRENGTH','CONCEPT_ANCESTOR')
foreach ($t in $tables) {
  $path = Get-TableFile -dir $vocabDir -table $t
  if ($path) { Bcp-Into-Staging -table $t -filePath $path }
}

Write-Host "`n[OK] Staging 완료. 스키마: $($cfg.StagingSchema), DB: $($cfg.Database)"
Write-Host "이제 변환 SQL로 [$($cfg.StagingSchema)] -> [$($cfg.CdmSchema)] 적재를 수행하세요."
