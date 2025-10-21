


pwsh scripts/deploy-omop.ps1


vocab 다운로드
vocab/vocab.zip

pwsh scripts/unzip-cdm-vocab.ps1

원본 소스 스키마에서 vocab 추출(csv 저장)

pwsh scripts/extract-src-vocab-to-csv.ps1 -ConfigPath ./.env -Files extract_measurement.sql