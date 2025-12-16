# ETL 변환 실행 가이드

이 문서는 iPlus EMR 데이터를 OMOP CDM으로 변환하는 전체 프로세스를 설명합니다. 환경 설정부터 DDL 배포, Vocabulary 적재, 그리고 최종 ETL 실행까지의 단계를 순서대로 기술합니다.

## 1. 사전 요구사항 (Prerequisites)

스크립트 실행을 위해 다음 도구들이 설치되어 있어야 합니다:

*   **PowerShell (pwsh)**: 스크립트 실행 환경
*   **SQLCMD**: SQL Server 쿼리 실행 도구
*   **BCP**: 대량 데이터 로드 도구 (Vocabulary 매핑 테이블 적재용)
*   **Unzip**: 압축 해제 도구 (Vocabulary 파일 처리용)

## 2. 환경 설정 (Configuration)

프로젝트 루트 디렉토리에 `.env` 파일을 생성하고 데이터베이스 접속 정보 및 스키마 정보를 설정해야 합니다. `env.default` 파일을 복사하여 `.env`로 이름을 변경하고 내용을 수정하세요.

```properties
# .env 예시
OMOP_SERVER=localhost
OMOP_DB=MyDB
OMOP_USER=sa
OMOP_PASSWORD=your_password
OMOP_CDM_SCHEMA=cdm
STAGING_SCHEMA=stg_cdm
SRC_SCHEMA=dbo
SQLCMD_BIN=sqlcmd
VOCAB_EXTRACT_DIR=vocab/extracted
```

## 3. 실행 단계 (Execution Steps)

전체 변환 과정은 다음 순서로 진행해야 합니다.

### Step 1: OMOP CDM 스키마 및 테이블 생성 (DDL Deployment)

CDM 스키마를 생성하고 필요한 테이블, 키, 인덱스, 제약조건을 생성합니다.

```powershell
pwsh scripts/deploy-omop.ps1
```

### Step 2: Vocabulary 준비 및 적재

OMOP 표준 Vocabulary 데이터를 CDM 테이블에 적재하는 과정입니다.

1.  **압축 해제**: `vocab/vocab.zip` (또는 지정된 경로) 파일을 압축 해제합니다.
    ```powershell
    # 기본값: vocab/vocab.zip -> vocab/extracted
    pwsh scripts/unzip-cdm-vocab.ps1 -ArchivePath vocab/vocab.zip
    ```

2.  **Staging 적재**: 압축 해제된 CSV 파일들을 Staging 스키마(`stg_cdm`)로 로드합니다.
    ```powershell
    pwsh scripts/load-vocab.ps1
    ```

3.  **CDM 이관**: Staging 테이블의 데이터를 최종 CDM 테이블로 이동합니다.
    ```powershell
    pwsh scripts/migrate-vocab.ps1
    ```

### Step 3: 소스 Vocabulary 추출 (선택 사항)

매핑 작업 등을 위해 소스 데이터(`dbo`)에서 코드 정보를 추출해야 하는 경우 실행합니다. 추출된 파일은 `vocab/extracted` (또는 설정된 경로)에 TSV 형태로 저장됩니다.

```powershell
pwsh scripts/extract-src-vocab-to-csv.ps1 -Files "extract_measurement.sql"
```

### Step 4: ETL 실행 (Main ETL)

실제 임상 데이터를 CDM으로 변환하여 적재합니다.

#### 4.1 전체 ETL 실행 (기본)

기본적으로 모든 매핑 테이블 생성 및 CDM 테이블 적재를 순차적으로 수행합니다.

```powershell
pwsh scripts/exec-etl-sql.ps1
```

#### 4.2 전체 초기화 후 실행 (Full Reload)

기존 데이터를 초기화(`reset.sql` 실행)하고 처음부터 다시 실행하려면 `-FullReload` 옵션을 사용합니다. 매핑 테이블까지 모두 초기화하려면 `-ResetMaps`를 함께 사용하세요.

```powershell
# 데이터 초기화 후 실행
pwsh scripts/exec-etl-sql.ps1 -FullReload

# 매핑 테이블까지 모두 초기화 후 실행 (완전 초기화)
pwsh scripts/exec-etl-sql.ps1 -FullReload -ResetMaps
```

#### 4.3 특정 테이블만 실행

특정 SQL 파일만 실행하고 싶은 경우 `-SqlFiles` 파라미터를 사용합니다.

```powershell
# person 테이블만 다시 적재
pwsh scripts/exec-etl-sql.ps1 -SqlFiles "etl-sql/person.sql"
```

## 4. 문제 해결 (Troubleshooting)

*   **암호 입력**: `.env` 파일에 암호를 저장하지 않은 경우 `-PromptPassword` 옵션을 사용하여 실행 시 암호를 입력받을 수 있습니다.
*   **경로 문제**: 모든 스크립트는 프로젝트 루트 디렉토리에서 실행하는 것을 권장합니다.
*   **인코딩**: 윈도우 환경에서는 UTF-8 처리를 위해 코드페이지 65001을 강제로 사용합니다.
*   **BCP 오류**: Vocabulary 적재 시 BCP 오류가 발생하면 `vocab/bcp-errors` 디렉토리의 로그를 확인하세요.
