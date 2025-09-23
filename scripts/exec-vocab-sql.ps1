param(
  [string]$Server,
  [string]$Database,
  [string]$User,
  [string]$Password,
  [string]$CdmSchema,
  [string]$ConfigPath,
  [switch]$UseEnv,
  [switch]$PromptPassword,
  [string]$InputSqlDir
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
  InputSqlDir  = (Join-Path (Get-RepoRoot) "vocab/sql")
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
    OMOP_SERVER    = "Server"
    OMOP_DB        = "Database"
    OMOP_USER      = "User"
    OMOP_PASSWORD  = "Password"
    OMOP_CDM_SCHEMA= "CdmSchema"
    SQLCMD_BIN     = "SqlcmdBin"
  }
  foreach ($k in $kvMap.Keys) { if ($map.ContainsKey($k)) { $config[$map[$k]] = $kvMap[$k] } }
}

$cfg = $defaults.Clone()
foreach ($k in $config.Keys) { if ($config[$k]) { $cfg[$k] = $config[$k] } }
if ($UseEnv) {
  $envMap = @{
    Server     = $env:OMOP_SERVER
    Database   = $env:OMOP_DB
    User       = $env:OMOP_USER
    Password   = $env:OMOP_PASSWORD
    CdmSchema  = $env:OMOP_CDM_SCHEMA
    SqlcmdBin  = $env:SQLCMD_BIN
  }
  foreach ($k in $envMap.Keys) { if ($envMap[$k]) { $cfg[$k] = $envMap[$k] } }
}
foreach ($name in $PSBoundParameters.Keys) { if ($name -in $cfg.Keys) { $cfg[$name] = $PSBoundParameters[$name] } }

function Require-Command($name) { if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Required command not found: $name" } }
Require-Command $cfg.SqlcmdBin

# Resolve input dir
$inDir = if ([IO.Path]::IsPathRooted($InputSqlDir)) { $InputSqlDir } elseif ($InputSqlDir) { Join-Path (Get-Location) $InputSqlDir } else { $cfg.InputSqlDir }
if (-not (Test-Path $inDir)) { throw "입력 SQL 디렉터리를 찾을 수 없습니다: $inDir" }

# Preflight
$commonArgs = @('-S', $cfg.Server, '-d', $cfg.Database, '-b', '-V', '16')
if ($cfg.User) { $commonArgs += @('-U', $cfg.User, '-P', $cfg.Password) } else { $commonArgs += @('-E') }
& $cfg.SqlcmdBin @commonArgs -Q "SELECT 1" | Out-Null

# Execute in file-name order
$files = Get-ChildItem -Path $inDir -File -Filter "*.sql" | Sort-Object Name
foreach ($f in $files) {
  Write-Host "[EXEC] $($f.FullName)"
  & $cfg.SqlcmdBin @commonArgs -i $f.FullName
  if ($LASTEXITCODE -ne 0) { throw "실행 실패: $($f.Name)" }
}

Write-Host "[OK] 모든 SQL 파일 실행 완료: $inDir"
