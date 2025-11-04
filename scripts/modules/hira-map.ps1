param(
  [Parameter(Mandatory = $false)][string]$BcpBin = 'bcp',
  [Parameter(Mandatory = $false)][int]$BcpCodePage = 65001
)

function Hira-QuoteIdent([string]$name) { return "[" + ($name -replace "]", "]]" ) + "]" }

function Hira-DetectRowTerminator([string]$filePath) {
  try {
    $fs = [System.IO.File]::OpenRead($filePath)
    try {
      $buf = New-Object byte[] 1048576
      $n = $fs.Read($buf, 0, $buf.Length)
      for ($i = 0; $i -lt ($n - 1); $i++) { if ($buf[$i] -eq 13 -and $buf[$i + 1] -eq 10) { return '0x0d0a' } }
      for ($i = 0; $i -lt $n; $i++) { if ($buf[$i] -eq 10) { return '0x0a' } }
    }
    finally { $fs.Close() }
  }
  catch {}
  return '0x0a'
}

function Hira-EnsureTrailingNewline([string]$filePath, [string]$rowTerm) {
  if (-not (Test-Path -LiteralPath $filePath)) { return }
  $bytes = if ($rowTerm -eq '0x0d0a') { [byte[]]@(13, 10) } else { [byte[]]@(10) }
  $fs = [System.IO.File]::Open($filePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
  try {
    $len = $fs.Length
    if ($len -ge $bytes.Length) {
      $fs.Seek(-[long]$bytes.Length, [System.IO.SeekOrigin]::End) | Out-Null
      $buf = New-Object byte[] $bytes.Length
      $null = $fs.Read($buf, 0, $buf.Length)
      $match = $true
      for ($i = 0; $i -lt $bytes.Length; $i++) { if ($buf[$i] -ne $bytes[$i]) { $match = $false; break } }
      if ($match) { return }
    }
    $fs.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
    $fs.Write($bytes, 0, $bytes.Length)
  }
  finally { $fs.Close() }
}

function Hira-EnsureDynamicStageTable([string]$sqlcmd, [object]$sqlcmdArgs, [string]$schema, [string]$table, [string]$filePath) {
  $qualified = (Hira-QuoteIdent $schema) + "." + (Hira-QuoteIdent $table)
  $objId = "$schema.$table"
  $header = Get-Content -LiteralPath $filePath -Encoding utf8 -TotalCount 1
  if (-not $header) { throw "헤더를 읽지 못했습니다: $filePath" }

  # 구분자 결정 (탭 우선, 없으면 콤마)
  $delim = if ($header.Contains("`t")) { "`t" } else { "," }
  $cols = $header -split $delim, [System.StringSplitOptions]::None | ForEach-Object { $_ -replace "\r$","" }
  $cols = $cols | ForEach-Object { $_.Trim() }
  if ($cols.Count -eq 0) { throw "헤더 컬럼이 없습니다: $filePath" }
  # 무명/중복 컬럼 처리
  $nameCount = @{}
  for ($i = 0; $i -lt $cols.Count; $i++) {
    $name = if ($cols[$i]) { $cols[$i] } else { "COL_" + ($i + 1) }
    if ($nameCount.ContainsKey($name)) { $nameCount[$name] += 1; $name = "$name" + '_' + $nameCount[$name] }
    else { $nameCount[$name] = 1 }
    $cols[$i] = $name
  }

  Write-Host ("[INFO] Ensure stage table: $qualified (cols=$($cols.Count))")

  # 드롭 후 최초 1컬럼 생성
  $dropSql = "IF OBJECT_ID('$objId','U') IS NOT NULL DROP TABLE $qualified;"
  & $sqlcmd @sqlcmdArgs -Q $dropSql | Out-Null

  $firstCol = Hira-QuoteIdent $cols[0]
  $createSql = "CREATE TABLE $qualified ($firstCol NVARCHAR(4000) NULL);"
  & $sqlcmd @sqlcmdArgs -Q $createSql | Out-Null

  for ($i = 1; $i -lt $cols.Count; $i++) {
    $q = Hira-QuoteIdent $cols[$i]
    $alter = "ALTER TABLE $qualified ADD $q NVARCHAR(4000) NULL;"
    & $sqlcmd @sqlcmdArgs -Q $alter | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "컬럼 추가 실패: $($cols[$i]) (exit=$LASTEXITCODE)" }
  }
}

function Hira-InvokeBcpImport([string]$server, [string]$database, [string]$user, [string]$password, [string]$schema, [string]$table, [string]$filePath, [string]$rowTerm, [string]$fieldDelimHex) {
  $dbtable = "$schema.$table"
  $auth = @('-S', $server, '-d', $database)
  if ($user) { $auth += @('-U', $user, '-P', $password) } else { $auth += @('-T') }
  $r = if ($rowTerm) { $rowTerm } else { '0x0d0a' }
  $t = if ($fieldDelimHex) { $fieldDelimHex } else { '0x2c' }
  $opts = @('-c', ('-t' + $t), ('-r' + $r), '-F', '2', '-k', '-e', (Join-Path ([System.IO.Path]::GetTempPath()) 'hira_map.bcp.err'))
  if ($BcpCodePage) { $opts += @('-C', $BcpCodePage.ToString()) }

  $authLog = @()
  for ($i = 0; $i -lt $auth.Count; $i++) {
    if ($auth[$i] -eq '-P' -and ($i + 1) -lt $auth.Count) { $authLog += @('-P', '******'); $i++; continue }
    $authLog += $auth[$i]
  }
  Write-Host ("[INFO] BCP: $BcpBin $dbtable in $filePath " + ($authLog -join ' ') + ' ' + ($opts -join ' '))

  & $BcpBin $dbtable in $filePath @auth @opts
  if ($LASTEXITCODE -ne 0) { throw "bcp 실패 (exit=$LASTEXITCODE): $dbtable" }
}

function Invoke-LoadHiraMap([string]$csvPath, [string]$stagingSchema, [string]$sqlcmd, [object]$sqlcmdArgs, [string]$server, [string]$database, [string]$user, [string]$password) {
  if (-not (Test-Path -LiteralPath $csvPath)) { throw "hira_map 파일을 찾지 못했습니다: $csvPath" }

  # 헤더를 보고 구분자/행종결자 결정
  $header = Get-Content -LiteralPath $csvPath -Encoding utf8 -TotalCount 1
  if (-not $header) { throw "헤더를 읽지 못했습니다: $csvPath" }
  $fieldDelimHex = if ($header.Contains("`t")) { '0x09' } else { '0x2c' }
  $rowTerm = Hira-DetectRowTerminator -filePath $csvPath

  Hira-EnsureTrailingNewline -filePath $csvPath -rowTerm $rowTerm

  # 동적 스테이지 테이블 생성 후 적재
  Hira-EnsureDynamicStageTable -sqlcmd $sqlcmd -sqlcmdArgs $sqlcmdArgs -schema $stagingSchema -table 'hira_map_stage' -filePath $csvPath
  Hira-InvokeBcpImport -server $server -database $database -user $user -password $password -schema $stagingSchema -table 'hira_map_stage' -filePath $csvPath -rowTerm $rowTerm -fieldDelimHex $fieldDelimHex

  $dest  = (Hira-QuoteIdent $stagingSchema) + '.[hira_map]'
  $stage = (Hira-QuoteIdent $stagingSchema) + '.[hira_map_stage]'

  $cSOURCE_DOMAIN_ID  = Hira-QuoteIdent 'SOURCE_DOMAIN_ID'
  $cLOCAL_CD1         = Hira-QuoteIdent 'LOCAL_CD1'
  $cLOCAL_CD1_NM      = Hira-QuoteIdent 'LOCAL_CD1_NM'
  $cTARGET_CONCEPT_ID = Hira-QuoteIdent 'TARGET_CONCEPT_ID_1'
  $cTARGET_DOMAIN_ID  = Hira-QuoteIdent 'TARGET_DOMAIN_ID'
  $cVALID_START_DATE  = Hira-QuoteIdent 'VALID_START_DATE'
  $cVALID_END_DATE    = Hira-QuoteIdent 'VALID_END_DATE'
  $cINVALID_REASON    = Hira-QuoteIdent 'INVALID_REASON'
  $cSEQ               = Hira-QuoteIdent 'SEQ'
  $cSOURCE_CONCEPT_ID = Hira-QuoteIdent 'SOURCE_CONCEPT_ID'

  $sql = @"
BEGIN TRY
  TRUNCATE TABLE $dest;
END TRY
BEGIN CATCH
  DELETE FROM $dest;
END CATCH

INSERT INTO $dest (
  SOURCE_DOMAIN_ID, LOCAL_CD1, LOCAL_CD1_NM, TARGET_CONCEPT_ID_1,
  TARGET_DOMAIN_ID, VALID_START_DATE, VALID_END_DATE, INVALID_REASON,
  SEQ, SOURCE_CONCEPT_ID
)
SELECT
  LEFT(CAST($cSOURCE_DOMAIN_ID  AS NVARCHAR(50)), 50),
  LEFT(CAST($cLOCAL_CD1         AS NVARCHAR(100)), 100),
  LEFT(CAST($cLOCAL_CD1_NM      AS NVARCHAR(500)), 500),
  TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(CAST($cTARGET_CONCEPT_ID AS NVARCHAR(100)))),'')) AS TARGET_CONCEPT_ID_1,
  LEFT(CAST($cTARGET_DOMAIN_ID  AS NVARCHAR(50)), 50),
  TRY_CONVERT(datetime, NULLIF(LTRIM(RTRIM(CAST($cVALID_START_DATE AS NVARCHAR(50)))),'')) AS VALID_START_DATE,
  TRY_CONVERT(datetime, NULLIF(LTRIM(RTRIM(CAST($cVALID_END_DATE   AS NVARCHAR(50)))),'')) AS VALID_END_DATE,
  LEFT(CAST($cINVALID_REASON    AS NVARCHAR(10)), 10),
  TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(CAST($cSEQ               AS NVARCHAR(100)))),'')) AS SEQ,
  TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(CAST($cSOURCE_CONCEPT_ID AS NVARCHAR(100)))),'')) AS SOURCE_CONCEPT_ID
FROM $stage;
"@

  & $sqlcmd @sqlcmdArgs -Q $sql | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "hira_map 적재 SQL 실패 (exit=$LASTEXITCODE)" }
}


