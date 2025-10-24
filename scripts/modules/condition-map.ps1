param(
  [Parameter(Mandatory=$false)][string]$BcpBin = 'bcp',
  [Parameter(Mandatory=$false)][int]$BcpCodePage = 65001
)

function Quote-Ident([string]$name) { return "[" + ($name -replace "]", "]]" ) + "]" }

function Write-ConditionMapTsv([string]$srcCsv, [string]$outPath) {
  if (-not (Test-Path -LiteralPath $srcCsv)) { throw "CSV 파일을 찾을 수 없습니다: $srcCsv" }
  $rows = Import-Csv -LiteralPath $srcCsv -Delimiter ',' -Encoding utf8
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  $sw = New-Object System.IO.StreamWriter($outPath, $false, $utf8NoBom)
  $sw.NewLine = "\r\n"
  try {
    foreach ($r in $rows) {
      $src = ($r.'상병코드'   | ForEach-Object { ($_ -replace "[\t\r\n]", " ") })
      $kor = ($r.'한글명칭'   | ForEach-Object { ($_ -replace "[\t\r\n]", " ") })
      $eng = ($r.'영문명칭'   | ForEach-Object { ($_ -replace "[\t\r\n]", " ") })
      $cid = ($r.'공통 Concept ID' | ForEach-Object { ($_ -replace "[\t\r\n]", " ") })
      $src = if ($src) { $src } else { '' }
      $kor = if ($kor) { $kor } else { '' }
      $eng = if ($eng) { $eng } else { '' }
      $cid = if ($cid) { $cid } else { '' }
      $line = "$src`t$kor`t$eng`t$cid"
      $sw.WriteLine($line)
    }
  } finally { $sw.Dispose() }
}

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
  # 무명 컬럼 대비
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
  $opts = @('-c', '-t0x09', ("-r" + $r), '-F', '2', '-k', '-e', (Join-Path ([System.IO.Path]::GetTempPath()) 'condition_map.bcp.err'))
  if ($BcpCodePage) { $opts += @('-C', $BcpCodePage.ToString()) }

  # Log (mask password)
  $authLog = @()
  for ($i=0; $i -lt $auth.Count; $i++) {
    if ($auth[$i] -eq '-P' -and ($i+1) -lt $auth.Count) { $authLog += @('-P', '******'); $i++; continue }
    $authLog += $auth[$i]
  }
  Write-Host ("[INFO] BCP: $BcpBin $dbtable in $filePath " + ($authLog -join ' ') + ' ' + ($opts -join ' '))

  & $BcpBin $dbtable in $filePath @auth @opts
  if ($LASTEXITCODE -ne 0) { throw "bcp 실패 (exit=$LASTEXITCODE): $dbtable" }
}

function Invoke-LoadConditionVocabularyMap([string]$csvPath, [string]$stagingSchema, [string]$sqlcmd, [object]$sqlcmdArgs, [string]$server, [string]$database, [string]$user, [string]$password) {
  if (-not (Test-Path -LiteralPath $csvPath)) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($csvPath)
    $dir  = [System.IO.Path]::GetDirectoryName($csvPath)
    $candidates = @(
      (Join-Path $dir ($base + '.tsv')),
      (Join-Path $dir ($base + '.csv')),
      (Join-Path $dir 'condition_map.tsv'),
      (Join-Path $dir 'condition_map.csv')
    )
    foreach ($p in $candidates) { if (Test-Path -LiteralPath $p) { $csvPath = $p; break } }
    if (-not (Test-Path -LiteralPath $csvPath)) { throw "condition_map 파일을 찾지 못했습니다: $csvPath" }
  }

  $ext = [System.IO.Path]::GetExtension($csvPath).ToLowerInvariant()
  $fileToLoad = $null
  $rowTerm = $null
  if ($ext -eq '.tsv' -or $ext -eq '.txt') {
    $fileToLoad = $csvPath
    $rowTerm = Detect-RowTerminator -filePath $fileToLoad
  } else {
    $tmpDir = [System.IO.Path]::GetTempPath()
    $tmpFile = Join-Path $tmpDir "condition_vocabulary_map.4cols.tsv"
    Write-ConditionMapTsv -srcCsv $csvPath -outPath $tmpFile
    $fileToLoad = $tmpFile
    $rowTerm = '0x0d0a'
  }

  # 행 종료 문자가 없으면 추가 (마지막 줄 개행 보장)
  Ensure-TrailingNewline -filePath $fileToLoad -rowTerm $rowTerm

  # 스테이징 테이블을 입력 파일 헤더 기반으로 동적 생성
  Ensure-DynamicStageTable -sqlcmd $sqlcmd -sqlcmdArgs $sqlcmdArgs -schema $stagingSchema -table 'condition_vocabulary_map_stage' -filePath $fileToLoad

  # stage는 create_condition_vocabulary_map.sql에서 보장됨
  Invoke-BcpImport -server $server -database $database -user $user -password $password -schema $stagingSchema -table 'condition_vocabulary_map_stage' -filePath $fileToLoad -rowTerm $rowTerm

  $dest = (Quote-Ident $stagingSchema) + '.[condition_vocabulary_map]'
  $stage = (Quote-Ident $stagingSchema) + '.[condition_vocabulary_map_stage]'
  $colSource = Quote-Ident '상병코드'
  $colKor    = Quote-Ident '한글명칭'
  $colEng    = Quote-Ident '영문명칭'
  $colCid    = Quote-Ident '공통 Concept ID'
  $sql = @"
BEGIN TRY
  TRUNCATE TABLE $dest;
END TRY
BEGIN CATCH
  DELETE FROM $dest;
END CATCH

INSERT INTO $dest (source_code, kor_name, eng_name, concept_id)
SELECT
  LEFT(CAST($colSource AS NVARCHAR(200)), 200),
  LEFT(CAST($colKor AS NVARCHAR(500)), 500),
  LEFT(CAST($colEng AS NVARCHAR(500)), 500),
  TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(CAST($colCid AS NVARCHAR(100)))),'')) AS concept_id
FROM $stage;
"@
  & $sqlcmd @sqlcmdArgs -Q $sql | Out-Null
}


