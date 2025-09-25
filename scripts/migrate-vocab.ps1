param(
  [string]$Server,
  [string]$Database,
  [string]$User,
  [string]$Password,
  [string]$CdmSchema,
  [string]$StagingSchema,
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

$defaults = @{
  Server       = "localhost"
  Database     = "MyDB"
  User         = ""
  Password     = ""
  CdmSchema    = "cdm"
  StagingSchema= "stg_cdm"
  SqlcmdBin    = "sqlcmd"
}

if (-not $ConfigPath) {
  $root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $defaultEnvScriptDir = Join-Path $root ".env"
  $defaultEnvRepoRoot  = Join-Path (Split-Path -Parent $root) ".env"
  if (Test-Path $defaultEnvScriptDir) { $ConfigPath = $defaultEnvScriptDir }
  elseif (Test-Path $defaultEnvRepoRoot) { $ConfigPath = $defaultEnvRepoRoot }
}

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
    OMOP_SERVER      = "Server"
    OMOP_DB          = "Database"
    OMOP_USER        = "User"
    OMOP_PASSWORD    = "Password"
    OMOP_CDM_SCHEMA  = "CdmSchema"
    STAGING_SCHEMA   = "StagingSchema"
    SQLCMD_BIN       = "SqlcmdBin"
  }
  foreach ($k in $kvMap.Keys) { if ($map.ContainsKey($k)) { $config[$map[$k]] = $kvMap[$k] } }
}

$cfg = $defaults.Clone()
foreach ($k in $config.Keys) { if ($config[$k]) { $cfg[$k] = $config[$k] } }
if ($UseEnv) {
  $envMap = @{
    Server       = $env:OMOP_SERVER
    Database     = $env:OMOP_DB
    User         = $env:OMOP_USER
    Password     = $env:OMOP_PASSWORD
    CdmSchema    = $env:OMOP_CDM_SCHEMA
    StagingSchema= $env:STAGING_SCHEMA
    SqlcmdBin    = $env:SQLCMD_BIN
  }
  foreach ($k in $envMap.Keys) { if ($envMap[$k]) { $cfg[$k] = $envMap[$k] } }
}
foreach ($name in $PSBoundParameters.Keys) { if ($name -in $cfg.Keys) { $cfg[$name] = $PSBoundParameters[$name] } }

function Require-Command($name) { if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Required command not found: $name" } }
Require-Command $cfg.SqlcmdBin

$commonArgs = @('-S', $cfg.Server, '-d', $cfg.Database, '-b', '-V', '16')
if ($cfg.User) {
  if (-not $cfg.Password -and $PromptPassword) {
    $secure = Read-Host -AsSecureString "Enter password for user '$($cfg.User)'"
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $cfg.Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
  }
  if (-not $cfg.Password) { throw "Password is required when User is set (or use -PromptPassword)" }
  $commonArgs += @('-U', $cfg.User, '-P', $cfg.Password)
} else { $commonArgs += @('-E') }

# Build migration SQL (DELETE then INSERT; then DROP staging)
$cdm = $cfg.CdmSchema
$stg = $cfg.StagingSchema
$sqlFile = Join-Path (Get-RepoRoot) "etl-sql/vocab/migrate_from_staging_to_cdm.sql"
if (!(Test-Path $sqlFile)) { throw "Migration SQL file not found: $sqlFile" }

# sqlcmd 변수 바인딩: CDM_SCHEMA, STG_SCHEMA
$args = @()
$args += @('-v', ('CDM_SCHEMA='+$cfg.CdmSchema))
$args += @('-v', ('STG_SCHEMA='+$cfg.StagingSchema))

Write-Host "[INFO] Vocabulary 마이그레이션 수행(파일): $sqlFile"
& $cfg.SqlcmdBin @commonArgs @args -i $sqlFile
if ($LASTEXITCODE -ne 0) { throw "Migration failed (exit=$LASTEXITCODE)" }
Write-Host "[OK] Vocabulary 마이그레이션 완료. CDM 스키마: $($cfg.CdmSchema)"


