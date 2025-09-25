param(
  [string]$Server,
  [string]$Database,
  [string]$User,
  [string]$Password,
  [string]$CdmSchema,
  [string]$StagingSchema,
  [string]$SrcSchema,
  [string]$ConfigPath,
  [switch]$UseEnv,
  [switch]$PromptPassword,
  [string]$SqlcmdBin
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  return (Split-Path -Parent $scriptRoot)
}

# Defaults
$defaults = @{
  Server         = "localhost"
  Database       = "MyDB"
  User           = ""
  Password       = ""
  CdmSchema      = "cdm"
  StagingSchema  = "stg_cdm"
  SrcSchema      = "dbo"
  SqlcmdBin      = "sqlcmd"
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
    OMOP_SERVER       = "Server"
    OMOP_DB           = "Database"
    OMOP_USER         = "User"
    OMOP_PASSWORD     = "Password"
    OMOP_CDM_SCHEMA   = "CdmSchema"
    STAGING_SCHEMA    = "StagingSchema"
    SRC_SCHEMA        = "SrcSchema"
    SQLCMD_BIN        = "SqlcmdBin"
  }
  foreach ($k in $kvMap.Keys) { if ($map.ContainsKey($k)) { $config[$map[$k]] = $kvMap[$k] } }
}

# Merge
$cfg = $defaults.Clone()
foreach ($k in $config.Keys) { if ($config[$k]) { $cfg[$k] = $config[$k] } }
if ($UseEnv) {
  $envMap = @{
    Server        = $env:OMOP_SERVER
    Database      = $env:OMOP_DB
    User          = $env:OMOP_USER
    Password      = $env:OMOP_PASSWORD
    CdmSchema     = $env:OMOP_CDM_SCHEMA
    StagingSchema = $env:STAGING_SCHEMA
    SrcSchema     = $env:SRC_SCHEMA
    SqlcmdBin     = $env:SQLCMD_BIN
  }
  foreach ($k in $envMap.Keys) { if ($envMap[$k]) { $cfg[$k] = $envMap[$k] } }
}
foreach ($name in $PSBoundParameters.Keys) { if ($name -in $cfg.Keys) { $cfg[$name] = $PSBoundParameters[$name] } }

# Prompt password
if (-not $cfg.Password -and $cfg.User -and $PromptPassword) {
  $secure = Read-Host -AsSecureString "Enter password for user '$($cfg.User)'"
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $cfg.Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Require-Command($name) { if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Required command not found: $name" } }
Require-Command $cfg.SqlcmdBin

# sqlcmd args
$sqlcmdArgs = @('-S', $cfg.Server, '-d', $cfg.Database, '-b', '-V', '16', '-I', '-v',
  "CdmSchema=$($cfg.CdmSchema)",
  "StagingSchema=$($cfg.StagingSchema)",
  "SrcSchema=$($cfg.SrcSchema)"
)
if ($cfg.User) {
  if (-not $cfg.Password) { throw "Password is required when User is set (or use -PromptPassword)" }
  $sqlcmdArgs += @('-U', $cfg.User, '-P', $cfg.Password)
} else {
  $sqlcmdArgs += @('-E')
}

# Resolve SQL files
$root = Get-RepoRoot
$stgFile   = Join-Path $root 'etl-sql/stg/create_person_id_map.sql'
$personSql = Join-Path $root 'etl-sql/person.sql'
if (-not (Test-Path $stgFile))   { throw "SQL not found: $stgFile" }
if (-not (Test-Path $personSql)) { throw "SQL not found: $personSql" }

# Execute in order
Write-Host "[EXEC] $stgFile"
& $cfg.SqlcmdBin @sqlcmdArgs -i $stgFile
if ($LASTEXITCODE -ne 0) { throw "실행 실패: $(Split-Path -Leaf $stgFile)" }

Write-Host "[EXEC] $personSql"
& $cfg.SqlcmdBin @sqlcmdArgs -i $personSql
if ($LASTEXITCODE -ne 0) { throw "실행 실패: $(Split-Path -Leaf $personSql)" }

Write-Host "[OK] ETL SQL 실행 완료 (CDM=$($cfg.CdmSchema), STG=$($cfg.StagingSchema), SRC=$($cfg.SrcSchema))"



