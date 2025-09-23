param(
  [string]$Server,
  [string]$Database,
  [string]$User,
  [string]$Password,
  [string]$CdmSchema,
  [string]$ConfigPath,         # config 파일(.json, .psd1, .env) 경로
  [switch]$UseEnv,             # 환경변수 사용
  [switch]$PromptPassword      # 비밀번호 미제공 시 프롬프트
)

# ---------- 기본값 ----------
$defaults = @{
  Server        = "localhost"
  Database      = "MyDB"
  User          = ""
  Password      = ""
  CdmSchema     = "cdm"
}

# ---------- 기본 ConfigPath (.env 자동 사용) ----------
if (-not $ConfigPath) {
  $root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $defaultEnvScriptDir = Join-Path $root ".env"
  $defaultEnvRepoRoot  = Join-Path (Split-Path -Parent $root) ".env"
  if (Test-Path $defaultEnvScriptDir) {
    $ConfigPath = $defaultEnvScriptDir
  } elseif (Test-Path $defaultEnvRepoRoot) {
    $ConfigPath = $defaultEnvRepoRoot
  }
}

# ---------- 설정파일 로드 (.json | .psd1 | .env) ----------
$config = @{}
if ($ConfigPath) {
  if (!(Test-Path $ConfigPath)) { throw "Config file not found: $ConfigPath" }
  $ext = [IO.Path]::GetExtension($ConfigPath).ToLowerInvariant()
  switch ($ext) {
    ".env" {
      $config = @{}
      Get-Content $ConfigPath | ForEach-Object {
        if ($_ -match '^\s*#') { return }              # comment
        if ($_ -match '^\s*$') { return }              # blank
        $kv = $_ -split '=',2
        if ($kv.Count -eq 2) {
          $k = $kv[0].Trim()
          $v = $kv[1].Trim()
          $config[$k] = $v
        }
      }
      # .env 키를 내부 키로 매핑
      $map = @{
        OMOP_SERVER         = "Server"
        OMOP_DB             = "Database"
        OMOP_USER           = "User"
        OMOP_PASSWORD       = "Password"
        OMOP_CDM_SCHEMA     = "CdmSchema"
      }
      $converted = @{}
      foreach ($k in $config.Keys) {
        if ($map.ContainsKey($k)) { $converted[$map[$k]] = $config[$k] }
      }
      $config = $converted
    }
    default { throw "Unsupported config extension: $ext (use .json | .psd1 | .env)" }
  }
}

function ConvertTo-Hashtable([object]$obj) {
  if ($obj -is [hashtable]) { return $obj }
  $ht = @{}
  $obj.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
  return $ht
}

# ---------- 환경변수 로드 ----------
$envMap = @{}
if ($UseEnv) {
  $envMap = @{
    Server        = $env:OMOP_SERVER
    Database      = $env:OMOP_DB
    User          = $env:OMOP_USER
    Password      = $env:OMOP_PASSWORD
    CdmSchema     = $env:OMOP_CDM_SCHEMA
  } | Where-Object { $_.Value } | ConvertTo-Hashtable
}

# ---------- 병합: 기본값 <- 설정파일 <- 환경변수 <- CLI ----------
$cfg = $defaults.Clone()
foreach ($k in $config.Keys)    { if ($config[$k])   { $cfg[$k] = $config[$k] } }
foreach ($k in $envMap.Keys)    { if ($envMap[$k])   { $cfg[$k] = $envMap[$k] } }
# CLI 인자(있으면 덮어씀)
foreach ($name in $PSBoundParameters.Keys) {
  if ($name -in $cfg.Keys) { $cfg[$name] = $PSBoundParameters[$name] }
}

# ---------- 비밀번호 프롬프트 ----------
if (-not $cfg.Password -and $cfg.User -and $PromptPassword) {
  $secure = Read-Host -AsSecureString "Enter password for user '$($cfg.User)'"
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $cfg.Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

# ---------- DDL 디렉터리 및 실행 대상 파일 정의 ----------
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ddlDirCandidates = @(
  (Join-Path $scriptRoot "ddl"),
  (Join-Path (Split-Path -Parent $scriptRoot) "ddl")
)
$ddlDir = $null
foreach ($d in $ddlDirCandidates) { if (Test-Path $d) { $ddlDir = $d; break } }
if (-not $ddlDir) { throw "DDL directory not found. Tried: $($ddlDirCandidates -join ', ')" }

$fileOrder = @(
  "OMOPCDM_sql_server_5.4_ddl.sql",
  "OMOPCDM_sql_server_5.4_primary_keys.sql",
  "OMOPCDM_sql_server_5.4_indices.sql",
  "OMOPCDM_sql_server_5.4_constraints.sql"
)

# ---------- 스키마 부트스트랩 문 ----------
$schemaBoot = @"
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = '$($cfg.CdmSchema)')    EXEC('CREATE SCHEMA $($cfg.CdmSchema)');
GO
"@

# ---------- sqlcmd 실행 ----------
$commonArgs = @(
  "-S", $cfg.Server,
  "-d", $cfg.Database,
  "-b",
  "-V", "15",
  "-I",
  "-v",
  "cdmDatabaseSchema=$($cfg.CdmSchema)"
)

# 파일들을 순서대로 실행
$isFirst = $true
foreach ($name in $fileOrder) {
  $path = Join-Path $ddlDir $name
  if (!(Test-Path $path)) { throw "DDL file not found: $path" }

  $raw = Get-Content -Raw $path
  $rendered = $raw -replace '@([A-Za-z0-9_]+)', '$$($1)'

  $contentToRun = if ($isFirst) { $schemaBoot + "`r`n" + $rendered } else { $rendered }
  $temp = New-TemporaryFile
  Set-Content -Path $temp -Value $contentToRun -Encoding UTF8

  if ([string]::IsNullOrWhiteSpace($cfg.User)) {
    & sqlcmd @commonArgs -i $temp -E
  } else {
    if (-not $cfg.Password) { throw "Password is required when -User is set (or use -PromptPassword)" }
    & sqlcmd @commonArgs -i $temp -U $cfg.User -P $cfg.Password
  }

  Remove-Item -Force $temp
  Write-Host "[OK] Executed:" $name
  $isFirst = $false
}

Write-Host "`n[OK] Completed executing DDL scripts in order for schema:" $cfg.CdmSchema