param(
  [Parameter(Position=0,Mandatory=$true)] [string]$ArchivePath,
  [string]$ConfigPath,
  [switch]$UseEnv,
  [string]$VocabExtractDir
)

function Get-RepoRoot {
  $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  return (Split-Path -Parent $scriptRoot)
}

# Defaults
$defaults = @{
  VocabExtractDir = Join-Path (Get-RepoRoot) "vocab/extracted"
}

# Auto-detect .env
if (-not $ConfigPath) {
  $root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $defaultEnvScriptDir = Join-Path $root ".env"
  $defaultEnvRepoRoot  = Join-Path (Split-Path -Parent $root) ".env"
  if (Test-Path $defaultEnvScriptDir) { $ConfigPath = $defaultEnvScriptDir }
  elseif (Test-Path $defaultEnvRepoRoot) { $ConfigPath = $defaultEnvRepoRoot }
}

# Load .env (only VOCAB_EXTRACT_DIR)
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
  if ($kvMap.ContainsKey('VOCAB_EXTRACT_DIR')) { $config['VocabExtractDir'] = $kvMap['VOCAB_EXTRACT_DIR'] }
}

# Merge
$cfg = $defaults.Clone()
foreach ($k in $config.Keys) { if ($config[$k]) { $cfg[$k] = $config[$k] } }
if ($UseEnv) {
  if ($env:VOCAB_EXTRACT_DIR) { $cfg['VocabExtractDir'] = $env:VOCAB_EXTRACT_DIR }
}
if ($VocabExtractDir) { $cfg.VocabExtractDir = $VocabExtractDir }

# Resolve paths
$zipFullPath = if ([IO.Path]::IsPathRooted($ArchivePath)) { $ArchivePath } else { Join-Path (Get-Location) $ArchivePath }
if (-not (Test-Path $zipFullPath)) { throw "zip 파일이 존재하지 않습니다: $zipFullPath" }
$null = New-Item -ItemType Directory -Force -Path $cfg.VocabExtractDir | Out-Null

# Extract
$unzip = Get-Command unzip -ErrorAction SilentlyContinue
$ext   = [IO.Path]::GetExtension($zipFullPath).ToLowerInvariant()
if ($unzip -and $ext -eq ".zip") {
  Write-Host "[INFO] 압축 해제(unzip) -> $($cfg.VocabExtractDir)"
  & unzip -o "$zipFullPath" -d "$($cfg.VocabExtractDir)" | Out-Null
} elseif ($ext -eq ".zip") {
  Write-Host "[INFO] 압축 해제(Expand-Archive) -> $($cfg.VocabExtractDir)"
  Expand-Archive -Force -Path "$zipFullPath" -DestinationPath "$($cfg.VocabExtractDir)"
} else {
  throw "지원 형식은 .zip 입니다. 현재: $ext"
}

Write-Host "[OK] 압축 해제 완료: $zipFullPath -> $($cfg.VocabExtractDir)"
