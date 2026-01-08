## 실행 가이드

### Repository 복사
```sh
git clone https://github.com/westhyena/iplus2cdm.git
```

### 환경 설정

1. 설정 파일 복사
```sh
cp env.default .env
```

2. 설정 파일 수정
```sh
vi .env
```
SQL Server, PostgreSQL, ATLAS 관련 정보 입력

### ETL 실행

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
```sh
pwsh scripts/deploy-omop-pg.ps1
```

#### CDM Vocabulary 로드
1. zip 파일 다운로드
* [구글 드라이브](https://drive.google.com/file/d/1r52Pc7dgeU45ah6WjEwze5KK1zGsylLA/view?usp=sharing)에서 다운로드 후, scp 등으로 전달

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
* [구글 드라이브](https://drive.google.com/file/d/1v2JhC4OmzvGDaz1SGYTQCa-TMIWptvnZ/view?usp=drive_link)에서 다운로드

2. 검안 매핑 파일 다운로드
* 구글 드라이브에서 다운로드
* 설치 병원마다 달라질 수 있음
  * 개발시 사용한 버전 [다운로드](https://drive.google.com/file/d/10Ccn5DCA2WwWmQjWgkJNjaPvwR8K7xgG/view?usp=sharing)

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

### ATLAS & Achilles 실행

#### Achilles

1. 설치
```sh
bin/install_achilles.sh

# 메세지 확인
# Achilles 설치가 성공적으로 완료되었습니다.
```

2. 실행
```
bin/run_achilles.sh

# 실행 후, 로그에서 실행 중 에러 발생하지 않았는지 확인
```

#### ATLAS

1. WebAPI 설치 및 실행
```sh
bin/install_webapi.sh
```

2. 실행 잘 되고 있는지 브라우저에서 확인

* 최초 실행시 로딩이 오래 걸릴 수 있음.
* 정상 로드 확인 필요
```
http://{ip}:8080/WebAPI/info

# json 출력이 올바르게 나오는지
```

3. 결과 스키마 초기화 및 데이터 입력
``sh
bin/init_webapi_results.sh

# 쿼리 실행이 오래 걸릴 수 있음
```

4. ATLAS 설치 및 실행
```sh
bin/install_atlas.sh
```
