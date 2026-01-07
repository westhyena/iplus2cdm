## 실행 가이드

#### 환경 설정

1. 설정 파일 복사
```sh
cp env.default .env
```

2. 설정 파일 수정
```sh
vi .env
```
SQL Server, PostgreSQL 접속 정보 입력

#### Prerequisites 설치
1. Powershell 설치
```sh
bin/install_powershell.sh
```

2. MSSQL Tools 설치
```sh
bin/install_mssql_tools.sh
```

[참고](https://learn.microsoft.com/ko-kr/sql/linux/sql-server-linux-setup-tools?view=sql-server-ver17&tabs=ubuntu-install%2Codbc-ubuntu-2404)

#### CDM 테이블 생성
1. 
```sh
pwsh scripts/deploy-omop-pg.ps1
```

#### CDM Vocabulary 로드
1. zip 파일 다운로드
* 구글 드라이브에서 다운로드 후, scp로 전달

2. 파일 이동
```sh
mv {파일명} vocab/vocab.zip
```

3. 압축 풀기
```sh
pwsh scripts/unzip-cdm-vocab.ps1 -ArchivePath vocab/vocab.zip

# vocab/extracted 폴더에 압축 해제됨.
```

4. Vocabulary 적재
```sh
pwsh scripts/load-vocab-pg.ps1 -VocabDir ./vocab/extracted/ -Force
```

#### Code Mapping 준비
1. 심평원 매핑 파일 다운로드
* 구글 드라이브에서 다운로드

2. 검안 매핑 파일 다운로드
* 구글 드라이브에서 다운로드
* 설치 병원마다 달라질 수 있음

3. 파일 이동
```sh
# 폴더 생성
mkdir -p vocab/mapping

# 두 파일 모두
mv {파일명} vocab/mapping
```

#### ETL 실행
```sh
pwsh scripts/exec-etl-bulk.ps1 -FullReload
```
