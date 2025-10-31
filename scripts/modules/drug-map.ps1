param(
  [Parameter(Mandatory=$false)][string]$BcpBin = 'bcp',
  [Parameter(Mandatory=$false)][int]$BcpCodePage = 65001
)

function Drug-QuoteIdent([string]$name) { return "[" + ($name -replace "]", "]]" ) + "]" }

function Write-DrugMapTsv([string]$srcCsv, [string]$outPath) {
  if (-not (Test-Path -LiteralPath $srcCsv)) { throw "CSV 파일을 찾을 수 없습니다: $srcCsv" }
  $rows = Import-Csv -LiteralPath $srcCsv -Delimiter ',' -Encoding utf8
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  $sw = New-Object System.IO.StreamWriter($outPath, $false, $utf8NoBom)
  $sw.NewLine = "\r\n"
  try {
    # 헤더: 청구코드, 한글명, TARGET_CONCEPT_ID_1, SOURCE_CONCEPT_ID
    $sw.WriteLine(("청구코드`t한글명`tTARGET_CONCEPT_ID_1`tSOURCE_CONCEPT_ID"))
    foreach ($r in $rows) {
      $code = ($r.'청구코드' | ForEach-Object { ($_ -replace "[\t\r\n]", " ") })
      $name = ($r.'한글명'   | ForEach-Object { ($_ -replace "[\t\r\n]", " ") })
      $tid  = ($r.'TARGET_CONCEPT_ID_1' | ForEach-Object { ($_ -replace "[\t\r\n]", " ") })
      $sid  = ($r.'SOURCE_CONCEPT_ID'   | ForEach-Object { ($_ -replace "[\t\r\n]", " ") })
      $code = if ($code) { $code } else { '' }
      $name = if ($name) { $name } else { '' }
      $tid  = if ($tid)  { $tid }  else { '' }
      $sid  = if ($sid)  { $sid }  else { '' }
      $line = "$code`t$name`t$tid`t$sid"
      $sw.WriteLine($line)
    }
  } finally { $sw.Dispose() }
}

function Write-DrugMapTsvFromTsv([string]$srcTsv, [string]$outPath) {
  if (-not (Test-Path -LiteralPath $srcTsv)) { throw "TSV 파일을 찾을 수 없습니다: $srcTsv" }
  $rows = Import-Csv -LiteralPath $srcTsv -Delimiter "`t" -Encoding utf8
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  $sw = New-Object System.IO.StreamWriter($outPath, $false, $utf8NoBom)
  $sw.NewLine = "\r\n"
  try {
    $sw.WriteLine(("청구코드`t한글명`tTARGET_CONCEPT_ID_1`tSOURCE_CONCEPT_ID"))
    foreach ($r in $rows) {
      $code = ($r.'청구코드' | ForEach-Object { ($_ -replace "[\t\r\n]", " ") })
      $name = ($r.'한글명'   | ForEach-Object { ($_ -replace "[\t\r\n]", " ") })
      $tid  = ($r.'TARGET_CONCEPT_ID_1' | ForEach-Object { ($_ -replace "[\t\r\n]", " ") })
      $sid  = ($r.'SOURCE_CONCEPT_ID'   | ForEach-Object { ($_ -replace "[\t\r\n]", " ") })
      $code = if ($code) { $code } else { '' }
      $name = if ($name) { $name } else { '' }
      $tid  = if ($tid)  { $tid }  else { '' }
      $sid  = if ($sid)  { $sid }  else { '' }
      $line = "$code`t$name`t$tid`t$sid"
      $sw.WriteLine($line)
    }
  } finally { $sw.Dispose() }
}

function Drug-DetectRowTerminator([string]$filePath) {
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

function Drug-EnsureTrailingNewline([string]$filePath, [string]$rowTerm) {
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

function Drug-EnsureDynamicStageTable([string]$sqlcmd, [object]$sqlcmdArgs, [string]$schema, [string]$table, [string]$filePath) {
  $qualified = (Drug-QuoteIdent $schema) + "." + (Drug-QuoteIdent $table)
  $objId = "$schema.$table"
  $header = Get-Content -LiteralPath $filePath -TotalCount 1
  if (-not $header) { throw "헤더를 읽지 못했습니다: $filePath" }
  
  # 구분자 결정 (탭 우선, 없으면 콤마)
  $delim = if ($header.Contains("`t")) { "`t" } else { "," }
  $cols = $header -split $delim, [System.StringSplitOptions]::None | ForEach-Object { $_ -replace "\r$","" }
  $cols = $cols | ForEach-Object { $_.Trim() }
  if ($cols.Count -eq 0) { throw "헤더 컬럼이 없습니다: $filePath" }
  # 무명 컬럼 대체 및 중복명 처리
  $nameCount = @{}
  for ($i=0; $i -lt $cols.Count; $i++) {
    $name = if ($cols[$i]) { $cols[$i] } else { "COL_" + ($i+1) }
    if ($nameCount.ContainsKey($name)) { $nameCount[$name] += 1; $name = "$name" + '_' + $nameCount[$name] }
    else { $nameCount[$name] = 1 }
    $cols[$i] = $name
  }

  Write-Host ("[INFO] Ensure stage table: $qualified (cols=$($cols.Count))")

  # 1) 삭제
  $dropSql = "IF OBJECT_ID('$objId','U') IS NOT NULL DROP TABLE $qualified;"
  & $sqlcmd @sqlcmdArgs -Q $dropSql | Out-Null

  # 2) 첫 컬럼으로 테이블 생성
  $firstCol = Drug-QuoteIdent $cols[0]
  $createSql = "CREATE TABLE $qualified ($firstCol NVARCHAR(4000) NULL);"
  & $sqlcmd @sqlcmdArgs -Q $createSql | Out-Null

  # 3) 나머지 컬럼은 ALTER TABLE로 순차 추가 (인자 길이 문제 회피)
  for ($i=1; $i -lt $cols.Count; $i++) {
    $q = Drug-QuoteIdent $cols[$i]
    $alter = "ALTER TABLE $qualified ADD $q NVARCHAR(4000) NULL;"
    & $sqlcmd @sqlcmdArgs -Q $alter | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "컬럼 추가 실패: $($cols[$i]) (exit=$LASTEXITCODE)" }
  }
}

function Drug-InvokeBcpImport([string]$server, [string]$database, [string]$user, [string]$password, [string]$schema, [string]$table, [string]$filePath, [string]$rowTerm) {
  $dbtable = "$schema.$table"
  $auth = @('-S', $server, '-d', $database)
  if ($user) { $auth += @('-U', $user, '-P', $password) } else { $auth += @('-T') }
  $r = if ($rowTerm) { $rowTerm } else { '0x0d0a' }
  $opts = @('-c', '-t0x09', ("-r" + $r), '-F', '2', '-k', '-e', (Join-Path ([System.IO.Path]::GetTempPath()) 'drug_map.bcp.err'))
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

function Invoke-LoadDrugVocabularyMap([string]$path, [string]$stagingSchema, [string]$sqlcmd, [object]$sqlcmdArgs, [string]$server, [string]$database, [string]$user, [string]$password) {
  if (-not (Test-Path -LiteralPath $path)) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $dir  = [System.IO.Path]::GetDirectoryName($path)
    $candidates = @(
      (Join-Path $dir ($base + '.csv')),
      (Join-Path $dir ($base + '.tsv')),
      (Join-Path $dir 'drug_map.tsv')
    )
    foreach ($p in $candidates) { if (Test-Path -LiteralPath $p) { $path = $p; break } }
    if (-not (Test-Path -LiteralPath $path)) { throw "drug map 파일을 찾지 못했습니다: $path" }
  }

  $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
  $fileToLoad = $path
  $rowTerm = Drug-DetectRowTerminator -filePath $fileToLoad

  Drug-EnsureTrailingNewline -filePath $fileToLoad -rowTerm $rowTerm

  Drug-EnsureDynamicStageTable -sqlcmd $sqlcmd -sqlcmdArgs $sqlcmdArgs -schema $stagingSchema -table 'drug_vocabulary_map_stage' -filePath $fileToLoad

  Drug-InvokeBcpImport -server $server -database $database -user $user -password $password -schema $stagingSchema -table 'drug_vocabulary_map_stage' -filePath $fileToLoad -rowTerm $rowTerm

  $dest  = (Drug-QuoteIdent $stagingSchema) + '.[drug_vocabulary_map]'
  $stage = (Drug-QuoteIdent $stagingSchema) + '.[drug_vocabulary_map_stage]'

  # 스테이지 테이블 실제 컬럼명 조회 후 존재하는 컬럼 우선 사용
  $header = Get-Content -LiteralPath $fileToLoad -TotalCount 1
  $del = if ($header.Contains("`t")) { "`t" } else { "," }
  $hcols = $header -split $del, [System.StringSplitOptions]::None | ForEach-Object { $_ -replace "\r$","" }
  $hcols = $hcols | ForEach-Object { $_.Trim() }
  # 후보군
  $codeName = ($hcols | Where-Object { $_ -eq '청구코드' -or $_ -eq '코드' } | Select-Object -First 1)
  $korName  = ($hcols | Where-Object { $_ -eq '한글명' -or $_ -eq '급여명' } | Select-Object -First 1)
  $tgtName  = ($hcols | Where-Object { $_ -eq 'TARGET_CONCEPT_ID_1' -or $_ -eq 'TARGET_CONCEPT_ID' } | Select-Object -First 1)
  $srcName  = ($hcols | Where-Object { $_ -eq 'SOURCE_CONCEPT_ID' } | Select-Object -First 1)

  if (-not $codeName) { throw "입력 파일에서 '청구코드'(또는 '코드') 컬럼을 찾을 수 없습니다." }
  if (-not $korName)  { $korName = '한글명' } # 없으면 빈값으로 들어감

  $colCode = Drug-QuoteIdent $codeName
  $colName = Drug-QuoteIdent $korName
  $colTgt  = if ($tgtName) { Drug-QuoteIdent $tgtName } else { '[__no_tgt__]' }
  $colSrc  = if ($srcName) { Drug-QuoteIdent $srcName } else { '[__no_src__]' }

  $sql = @"
BEGIN TRY
  TRUNCATE TABLE $dest;
END TRY
BEGIN CATCH
  DELETE FROM $dest;
END CATCH

INSERT INTO $dest (source_code, source_Name, target_concept_id, source_concept_id)
SELECT
  LEFT(CAST($colCode AS NVARCHAR(200)), 200) AS source_code,
  LEFT(CAST($colName AS NVARCHAR(500)), 500) AS source_Name,
  CASE WHEN COL_LENGTH('$($stagingSchema).drug_vocabulary_map_stage', REPLACE('$tgtName','''','''''')) IS NOT NULL
       THEN TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(CAST($colTgt AS NVARCHAR(100)))),''))
       ELSE NULL END AS target_concept_id,
  CASE WHEN COL_LENGTH('$($stagingSchema).drug_vocabulary_map_stage', REPLACE('$srcName','''','''''')) IS NOT NULL
       THEN TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(CAST($colSrc AS NVARCHAR(100)))),''))
       ELSE NULL END AS source_concept_id
FROM $stage;
"@
  & $sqlcmd @sqlcmdArgs -Q $sql | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "drug_vocabulary_map 적재 SQL 실패 (exit=$LASTEXITCODE)" }
}


