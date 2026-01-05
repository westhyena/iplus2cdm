param(
  [Parameter(Mandatory=$false)][string]$BcpBin = 'bcp',
  [Parameter(Mandatory=$false)][int]$BcpCodePage = 65001
)

function Quote-Ident([string]$name) { return "[" + ($name -replace "]", "]]" ) + "]" }

function Detect-RowTerminator([string]$filePath) {
  try {
    $fs = [System.IO.File]::OpenRead($filePath)
    try {
      $buf = New-Object byte[] 1048576
      $n = $fs.Read($buf, 0, $buf.Length)
      for ($i=0; $i -lt ($n - 1); $i++) { if ($buf[$i] -eq 13 -and $buf[$i+1] -eq 10) { return '0x0d0a' } }
      for ($i=0; $i -lt $n; $i++) { if ($buf[$i] -eq 10) { return '0x0a' } }
    } finally { $fs.Close() }
  } catch {}
  return '0x0a'
}

function Ensure-TrailingNewline([string]$filePath, [string]$rowTerm) {
  if (-not (Test-Path -LiteralPath $filePath)) { return }
  $bytes = if ($rowTerm -eq '0x0d0a') { [byte[]]@(13,10) } else { [byte[]]@(10) }
  $fs = [System.IO.File]::Open($filePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
  try {
    $len = $fs.Length
    if ($len -ge $bytes.Length) {
      $fs.Seek(-[long]$bytes.Length, [System.IO.SeekOrigin]::End) | Out-Null
      $buf = New-Object byte[] $bytes.Length
      $null = $fs.Read($buf, 0, $buf.Length)
      $match = $true
      for ($i=0; $i -lt $bytes.Length; $i++) { if ($buf[$i] -ne $bytes[$i]) { $match = $false; break } }
      if ($match) { return }
    }
    $fs.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
    $fs.Write($bytes, 0, $bytes.Length)
  } finally { $fs.Close() }
}

function Ensure-DynamicStageTable([string]$sqlcmd, [object]$sqlcmdArgs, [string]$schema, [string]$table, [string]$filePath) {
  $qualified = (Quote-Ident $schema) + "." + (Quote-Ident $table)
  $objId = "$schema.$table"
  $header = Get-Content -LiteralPath $filePath -TotalCount 1
  if (-not $header) { throw "헤더를 읽지 못했습니다: $filePath" }
  $cols = $header -split "`t", [System.StringSplitOptions]::None | ForEach-Object { $_ -replace "\r$","" }
  $cols = $cols | ForEach-Object { $_.Trim() }
  if ($cols.Count -eq 0) { throw "헤더 컬럼이 없습니다: $filePath" }
  for ($i=0; $i -lt $cols.Count; $i++) { if (-not $cols[$i]) { $cols[$i] = "COL_" + ($i+1) } }
  $colsQuoted = $cols | ForEach-Object { Quote-Ident $_ }
  $colsDef = ($colsQuoted | ForEach-Object { "$_ NVARCHAR(4000) NULL" }) -join ","
  $sql = @"
IF OBJECT_ID('$objId','U') IS NOT NULL DROP TABLE $qualified;
CREATE TABLE $qualified ($colsDef);
"@
  & $sqlcmd @sqlcmdArgs -Q $sql | Out-Null
}

function Invoke-BcpImport([string]$server, [string]$database, [string]$user, [string]$password, [string]$schema, [string]$table, [string]$filePath, [string]$rowTerm) {
  $dbtable = "$schema.$table"
  $auth = @('-S', $server, '-d', $database)
  if ($user) { $auth += @('-U', $user, '-P', $password) } else { $auth += @('-T') }
  $r = if ($rowTerm) { $rowTerm } else { '0x0d0a' }
  $opts = @('-c', '-t0x09', ("-r" + $r), '-F', '2', '-k', '-e', (Join-Path ([System.IO.Path]::GetTempPath()) 'measurement_map.bcp.err'), '-u')
  if ($BcpCodePage) { $opts += @('-C', $BcpCodePage.ToString()) }

  $authLog = @()
  for ($i=0; $i -lt $auth.Count; $i++) {
    if ($auth[$i] -eq '-P' -and ($i+1) -lt $auth.Count) { $authLog += @('-P', '******'); $i++; continue }
    $authLog += $auth[$i]
  }
  Write-Host ("[INFO] BCP: $BcpBin $dbtable in $filePath " + ($authLog -join ' ') + ' ' + ($opts -join ' '))

  & $BcpBin $dbtable in $filePath @auth @opts
  if ($LASTEXITCODE -ne 0) { throw "bcp 실패 (exit=$LASTEXITCODE): $dbtable" }
}

function Invoke-LoadMeasurementVocabularyMap([string]$tsvPath, [string]$stagingSchema, [string]$sqlcmd, [object]$sqlcmdArgs, [string]$server, [string]$database, [string]$user, [string]$password) {
  if (-not (Test-Path -LiteralPath $tsvPath)) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($tsvPath)
    $dir  = [System.IO.Path]::GetDirectoryName($tsvPath)
    $candidates = @(
      (Join-Path $dir ($base + '.tsv')),
      (Join-Path $dir 'measurement_map.tsv')
    )
    foreach ($p in $candidates) { if (Test-Path -LiteralPath $p) { $tsvPath = $p; break } }
    if (-not (Test-Path -LiteralPath $tsvPath)) { throw "measurement_map 파일을 찾지 못했습니다: $tsvPath" }
  }

  $ext = [System.IO.Path]::GetExtension($tsvPath).ToLowerInvariant()
  if ($ext -ne '.tsv' -and $ext -ne '.txt') { throw "지원하지 않는 확장자입니다: $ext (tsv/txt만 지원)" }
  $fileToLoad = $tsvPath
  $rowTerm = Detect-RowTerminator -filePath $fileToLoad

  Ensure-TrailingNewline -filePath $fileToLoad -rowTerm $rowTerm
  Ensure-DynamicStageTable -sqlcmd $sqlcmd -sqlcmdArgs $sqlcmdArgs -schema $stagingSchema -table 'measurement_vocabulary_map_stage' -filePath $fileToLoad
  Invoke-BcpImport -server $server -database $database -user $user -password $password -schema $stagingSchema -table 'measurement_vocabulary_map_stage' -filePath $fileToLoad -rowTerm $rowTerm

  $dest  = (Quote-Ident $stagingSchema) + '.[measurement_vocabulary_map]'
  $stage = (Quote-Ident $stagingSchema) + '.[measurement_vocabulary_map_stage]'
  $colLABNM = Quote-Ident 'LABNM'
  $colItem  = Quote-Ident 'ItemName'
  $colCommon = Quote-Ident '공통 OMOP ID'
  $colRightEye = Quote-Ident '좌안 OMOP ID'   # 사용자 매핑: 좌안 -> right_concept_id
  $colLeftEye  = Quote-Ident '우안 OMOP ID'   # 사용자 매핑: 우안 -> left_concept_id

  $sql = @"
BEGIN TRY
  TRUNCATE TABLE $dest;
END TRY
BEGIN CATCH
  DELETE FROM $dest;
END CATCH

INSERT INTO $dest (LABNM, ItemName, common_concept_id, right_concept_id, left_concept_id)
SELECT
  LEFT(CAST($colLABNM AS NVARCHAR(500)), 500),
  LEFT(CAST($colItem  AS NVARCHAR(500)), 500),
  TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(CAST($colCommon  AS NVARCHAR(100)))),'')) AS common_concept_id,
  TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(CAST($colRightEye AS NVARCHAR(100)))),'')) AS right_concept_id,
  TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(CAST($colLeftEye  AS NVARCHAR(100)))),'')) AS left_concept_id
FROM $stage;
"@
  & $sqlcmd @sqlcmdArgs -Q $sql | Out-Null
}


