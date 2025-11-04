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
  [string]$SqlcmdBin,
  [string[]]$SqlFiles,
  [switch]$FullReload,
  [switch]$ResetMaps,
  [string]$ConditionMapCsvPath,
  [string]$DrugMapPath,
  [string]$MeasurementMapTsvPath,
  [string]$HiraMapCsvPath,
  [string]$BcpBin,
  [int]$BcpCodePage
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
  ConditionMapCsvPath = (Join-Path (Get-RepoRoot) "vocab/mapping/condition_map.tsv")
  DrugMapPath    = (Join-Path (Get-RepoRoot) "vocab/mapping/drug_map.tsv")
  MeasurementMapTsvPath = (Join-Path (Get-RepoRoot) "vocab/mapping/measurement_map.tsv")
  HiraMapCsvPath = (Join-Path (Get-RepoRoot) "vocab/mapping/hira_map.tsv")
  BcpBin         = "bcp"
  BcpCodePage    = 65001
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
Require-Command $cfg.BcpBin

# sqlcmd args
$sqlcmdArgs = @('-S', $cfg.Server, '-d', $cfg.Database, '-b', '-V', '16', '-I', '-v',
  "CdmSchema=$($cfg.CdmSchema)",
  "StagingSchema=$($cfg.StagingSchema)",
  "SrcSchema=$($cfg.SrcSchema)"
)
# Windows 환경에서 UTF-8 스크립트를 안정적으로 처리하기 위해 코드페이지를 강제합니다.
if ($IsWindows) {
  $sqlcmdArgs += @('-f', '65001')
}
# Auth args
if ($cfg.User) {
  if (-not $cfg.Password) { throw "Password is required when User is set (or use -PromptPassword)" }
  $sqlcmdArgs += @('-U', $cfg.User, '-P', $cfg.Password)
} else {
  $sqlcmdArgs += @('-E')
}

# Full reload: execute reset.sql and optionally reset staging maps
if ($FullReload) {
  $root = Get-RepoRoot
  $resetPath = Join-Path $root 'etl-sql/stg/reset.sql'
  if (-not (Test-Path $resetPath)) { throw "reset.sql not found: $resetPath" }
  $resetStart = Get-Date
  Write-Host "[RESET] Executing $resetPath"
  & $cfg.SqlcmdBin @sqlcmdArgs -i $resetPath
  $resetElapsed = (Get-Date) - $resetStart
  Write-Host "[TIME][RESET] reset.sql 실행 시간: $($resetElapsed.ToString('hh\:mm\:ss\.fff'))"
  if ($LASTEXITCODE -ne 0) { throw "reset.sql execution failed" }

  if ($ResetMaps) {
    Write-Host "[PURGE] Reset staging maps"
    $purgeStart = Get-Date
    $resetMapsSql = @"
IF OBJECT_ID('$($cfg.StagingSchema).person_id_map','U') IS NOT NULL TRUNCATE TABLE [$($cfg.StagingSchema)].[person_id_map];
IF OBJECT_ID('$($cfg.StagingSchema).visit_occurrence_map','U') IS NOT NULL TRUNCATE TABLE [$($cfg.StagingSchema)].[visit_occurrence_map];
"@
    & $cfg.SqlcmdBin @sqlcmdArgs -Q $resetMapsSql
    $purgeElapsed = (Get-Date) - $purgeStart
    Write-Host "[TIME][PURGE] ResetMaps 실행 시간: $($purgeElapsed.ToString('hh\:mm\:ss\.fff'))"
    if ($LASTEXITCODE -ne 0) { throw "ResetMaps purge failed" }
  }
}

if ($cfg.User) {
  if (-not $cfg.Password) { throw "Password is required when User is set (or use -PromptPassword)" }
  $sqlcmdArgs += @('-U', $cfg.User, '-P', $cfg.Password)
} else {
  $sqlcmdArgs += @('-E')
}

# 도메인별 로더 모듈 로드 (condition map)
$root = Get-RepoRoot
$condModule = Join-Path $root 'scripts/modules/condition-map.ps1'
if (Test-Path $condModule) { . $condModule }

# 도메인별 로더 모듈 로드 (drug map)
$drugModule = Join-Path $root 'scripts/modules/drug-map.ps1'
if (Test-Path $drugModule) { . $drugModule }

# 도메인별 로더 모듈 로드 (measurement map)
$measModule = Join-Path $root 'scripts/modules/measurement-map.ps1'
if (Test-Path $measModule) { . $measModule }

# 도메인별 로더 모듈 로드 (hira map)
$hiraModule = Join-Path $root 'scripts/modules/hira-map.ps1'
if (Test-Path $hiraModule) { . $hiraModule }

# Resolve SQL files
$root = Get-RepoRoot

# 기본 실행 목록 (상대경로, 리포지토리 루트 기준)
$defaultSqlRelPaths = @(
  'etl-sql/stg/create_person_id_map.sql',
  'etl-sql/stg/create_visit_occurrence_map.sql',
  'etl-sql/stg/create_condition_vocabulary_map.sql',
  'etl-sql/stg/create_measurement_vocabulary_map.sql',
  'etl-sql/stg/create_drug_vocabulary_map.sql',
  'etl-sql/stg/create_hira_map.sql',
  # 'etl-sql/stg/create_vocabulary_map.sql',
  'etl-sql/person.sql',
  'etl-sql/visit_occurrence.sql',
  'etl-sql/observation_period.sql',
  'etl-sql/drug_exposure.sql',
    'etl-sql/procedure_occurrence.sql',
  'etl-sql/condition_occurrence.sql',
  'etl-sql/measurement.sql'
)

# 사용자 지정이 없으면 기본 목록 사용
$candidatePaths = if ($SqlFiles -and $SqlFiles.Count -gt 0) { $SqlFiles } else { $defaultSqlRelPaths }

# 순차 실행
$overallStart = Get-Date
foreach ($pathLike in $candidatePaths) {
  $path = if ([IO.Path]::IsPathRooted($pathLike)) { $pathLike } else { Join-Path $root $pathLike }
  if (-not (Test-Path $path)) { throw "SQL not found: $path" }
  $fileName = Split-Path -Leaf $path
  $start = Get-Date
  Write-Host "[EXEC] $path"
  & $cfg.SqlcmdBin @sqlcmdArgs -i $path
  $exit = $LASTEXITCODE
  $elapsed = (Get-Date) - $start
  Write-Host "[TIME] $fileName 실행 시간: $($elapsed.ToString('hh\:mm\:ss\.fff'))"
  if ($exit -ne 0) { throw "실행 실패: $fileName" }

  # After creating condition_vocabulary_map, load data from CSV via bulk copy
  if ($fileName -eq 'create_condition_vocabulary_map.sql') {
    try {
      if (Get-Command Invoke-LoadConditionVocabularyMap -ErrorAction SilentlyContinue) {
        Invoke-LoadConditionVocabularyMap -csvPath $cfg.ConditionMapCsvPath -stagingSchema $cfg.StagingSchema -sqlcmd $cfg.SqlcmdBin -sqlcmdArgs $sqlcmdArgs -server $cfg.Server -database $cfg.Database -user $cfg.User -password $cfg.Password
      } else {
        throw 'Invoke-LoadConditionVocabularyMap 모듈을 찾지 못했습니다. scripts/modules/condition-map.ps1 로드를 확인하세요.'
      }
    } catch {
      throw "condition_vocabulary_map 적재 실패: $($_.Exception.Message)"
    }
  }
  elseif ($fileName -eq 'create_drug_vocabulary_map.sql') {
    try {
      if (Get-Command Invoke-LoadDrugVocabularyMap -ErrorAction SilentlyContinue) {
        Invoke-LoadDrugVocabularyMap -path $cfg.DrugMapPath -stagingSchema $cfg.StagingSchema -sqlcmd $cfg.SqlcmdBin -sqlcmdArgs $sqlcmdArgs -server $cfg.Server -database $cfg.Database -user $cfg.User -password $cfg.Password
      } else {
        throw 'Invoke-LoadDrugVocabularyMap 모듈을 찾지 못했습니다. scripts/modules/drug-map.ps1 로드를 확인하세요.'
      }
    } catch {
      throw "drug_vocabulary_map 적재 실패: $($_.Exception.Message)"
    }
  }
  elseif ($fileName -eq 'create_measurement_vocabulary_map.sql') {
    try {
      if (Get-Command Invoke-LoadMeasurementVocabularyMap -ErrorAction SilentlyContinue) {
        Invoke-LoadMeasurementVocabularyMap -tsvPath $cfg.MeasurementMapTsvPath -stagingSchema $cfg.StagingSchema -sqlcmd $cfg.SqlcmdBin -sqlcmdArgs $sqlcmdArgs -server $cfg.Server -database $cfg.Database -user $cfg.User -password $cfg.Password
      } else {
        throw 'Invoke-LoadMeasurementVocabularyMap 모듈을 찾지 못했습니다. scripts/modules/measurement-map.ps1 로드를 확인하세요.'
      }
    } catch {
      throw "measurement_vocabulary_map 적재 실패: $($_.Exception.Message)"
    }
  }
  elseif ($fileName -eq 'create_hira_map.sql') {
    try {
      if (Get-Command Invoke-LoadHiraMap -ErrorAction SilentlyContinue) {
        Invoke-LoadHiraMap -csvPath $cfg.HiraMapCsvPath -stagingSchema $cfg.StagingSchema -sqlcmd $cfg.SqlcmdBin -sqlcmdArgs $sqlcmdArgs -server $cfg.Server -database $cfg.Database -user $cfg.User -password $cfg.Password
      } else {
        throw 'Invoke-LoadHiraMap 모듈을 찾지 못했습니다. scripts/modules/hira-map.ps1 로드를 확인하세요.'
      }
    } catch {
      throw "hira_map 적재 실패: $($_.Exception.Message)"
    }
  }
}

$overallElapsed = (Get-Date) - $overallStart
Write-Host "[OK] ETL SQL 실행 완료 (CDM=$($cfg.CdmSchema), STG=$($cfg.StagingSchema), SRC=$($cfg.SrcSchema)) | 총 소요: $($overallElapsed.ToString('hh\:mm\:ss\.fff'))"



