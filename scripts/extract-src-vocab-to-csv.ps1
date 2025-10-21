param(
  [string]$Server,
  [string]$Database,
  [string]$User,
  [string]$Password,
  [string]$SrcSchema,
  [string]$ConfigPath,
  [switch]$UseEnv,
  [switch]$PromptPassword,
  [string]$SqlcmdBin,
  [string]$OutputDir,
  [string[]]$Files
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  return (Split-Path -Parent $scriptRoot)
}

# Defaults
$defaults = @{
  Server     = "localhost"
  Database   = "MyDB"
  User       = ""
  Password   = ""
  SrcSchema  = "dbo"
  SqlcmdBin  = "sqlcmd"
  OutputDir  = (Join-Path (Get-RepoRoot) "vocab/extracted")
}

# Auto-detect .env
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
    OMOP_SERVER   = "Server"
    OMOP_DB       = "Database"
    OMOP_USER     = "User"
    OMOP_PASSWORD = "Password"
    SRC_SCHEMA    = "SrcSchema"
    SQLCMD_BIN    = "SqlcmdBin"
    VOCAB_EXTRACT_DIR = "OutputDir"
  }
  foreach ($k in $kvMap.Keys) { if ($map.ContainsKey($k)) { $config[$map[$k]] = $kvMap[$k] } }
}

# Merge
$cfg = $defaults.Clone()
foreach ($k in $config.Keys) { if ($config[$k]) { $cfg[$k] = $config[$k] } }
if ($UseEnv) {
  $envMap = @{
    Server    = $env:OMOP_SERVER
    Database  = $env:OMOP_DB
    User      = $env:OMOP_USER
    Password  = $env:OMOP_PASSWORD
    SrcSchema = $env:SRC_SCHEMA
    SqlcmdBin = $env:SQLCMD_BIN
    OutputDir = $env:VOCAB_EXTRACT_DIR
  }
  foreach ($k in $envMap.Keys) { if ($envMap[$k]) { $cfg[$k] = $envMap[$k] } }
}
foreach ($name in $PSBoundParameters.Keys) { if ($name -in $cfg.Keys) { $cfg[$name] = $PSBoundParameters[$name] } }

# Prompt password if needed
if (-not $cfg.Password -and $cfg.User -and $PromptPassword) {
  $secure = Read-Host -AsSecureString "Enter password for user '$($cfg.User)'"
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $cfg.Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Require-Command($name) { if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Required command not found: $name" } }
Require-Command $cfg.SqlcmdBin

# Resolve output dir
$outDir = if ([IO.Path]::IsPathRooted($cfg.OutputDir)) { $cfg.OutputDir } else { Join-Path (Get-Location) $cfg.OutputDir }
$null = New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Build sqlcmd common args
$sqlcmdArgs = @('-S', $cfg.Server, '-d', $cfg.Database, '-b', '-V', '16', '-I', '-v', ("SrcSchema="+$cfg.SrcSchema))
if ($IsWindows) { $sqlcmdArgs += @('-f','65001') }
if ($cfg.User) {
  if (-not $cfg.Password) { throw "Password is required when User is set (or use -PromptPassword)" }
  $sqlcmdArgs += @('-U', $cfg.User, '-P', $cfg.Password)
} else { $sqlcmdArgs += @('-E') }

# Find extract SQL files
$root = Get-RepoRoot
$extractDir = Join-Path $root 'etl-sql/vocab'
if (-not (Test-Path $extractDir)) { throw "extract 디렉터리를 찾을 수 없습니다: $extractDir" }

function Resolve-ExtractFiles([string[]]$filesParam) {
  if ($filesParam -and $filesParam.Count -gt 0) {
    $resolved = @()
    foreach ($f in $filesParam) {
      $p = if ([IO.Path]::IsPathRooted($f)) { $f } else { Join-Path $extractDir $f }
      if (-not (Test-Path $p)) { throw "지정한 파일을 찾을 수 없습니다: $f" }
      $resolved += $p
    }
    return ,($resolved | Sort-Object)
  } else {
    return ,(Get-ChildItem -Path $extractDir -File -Filter 'extract_*.sql' | Sort-Object Name | ForEach-Object { $_.FullName })
  }
}

$filesToRun = Resolve-ExtractFiles -filesParam $Files
if (-not $filesToRun -or $filesToRun.Count -eq 0) { throw "실행할 extract_*.sql 파일이 없습니다." }

function Get-OutputPath([string]$sqlPath) {
  $name = [IO.Path]::GetFileNameWithoutExtension($sqlPath) # e.g., extract_measurement
  $tsv = "$name.tsv"
  return (Join-Path $outDir $tsv)
}

# Run each file and write output directly to TSV via sqlcmd -o
foreach ($sqlPath in $filesToRun) {
  $fileName = Split-Path -Leaf $sqlPath
  $outPath = Get-OutputPath -sqlPath $sqlPath
  Write-Host "[EXEC] $fileName -> $outPath"

  # 임시 SQL 생성: SET NOCOUNT ON; 을 프리펜드하여 (n rows affected) 제거
  $tmpSql = [System.IO.Path]::GetTempFileName()
  try {
    $original = Get-Content -LiteralPath $sqlPath -Raw
    $prefixed = "SET NOCOUNT ON;`n" + $original
    Set-Content -LiteralPath $tmpSql -Value $prefixed -Encoding UTF8

    # TSV 옵션: -s(구분자=TAB), -W(공백 트림), -o(파일로 직접 쓰기)
    $args = @()
    $args += $sqlcmdArgs
    $args += @('-s', "`t")
    $args += @('-W')
    $args += @('-i', $tmpSql)
    $args += @('-o', $outPath)

    & $cfg.SqlcmdBin @args
    if ($LASTEXITCODE -ne 0) { throw "실행 실패: $fileName (exit=$LASTEXITCODE)" }
    Write-Host "[OK] Wrote: $outPath"
  }
  finally {
    if (Test-Path $tmpSql) { Remove-Item -LiteralPath $tmpSql -Force -ErrorAction SilentlyContinue }
  }
}

Write-Host "[OK] 모든 extract SQL 실행 및 TSV 저장 완료. 출력: $outDir"


