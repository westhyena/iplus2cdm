#!/bin/bash

# 에러 발생 시 중단
set -e

echo "--- Achilles 설치를 시작합니다 (Ubuntu) ---"

# 1. 시스템 의존성 패키지 업데이트 및 설치
echo "1. 시스템 패키지 설치 중..."
sudo apt update
sudo apt install -y \
    r-base \
    r-base-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libpng-dev \
    default-jdk \
    pkg-config \
    openjdk-11-jdk \
    r-cran-rjava

# 2. Java 환경 설정 (rJava 연동을 위함)
echo "2. Java 환경 재설정 중..."
sudo JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64 PATH=$PATH:$JAVA_HOME/bin R CMD javareconf

# 3. R 패키지 설치 (Heredoc을 사용하여 R 스크립트 실행)
echo "3. R 패키지 및 Achilles 설치 중 (시간이 소요될 수 있습니다)..."
sudo R --vanilla <<EOF
# CRAN 미러 설정
options(repos = c(CRAN = "https://cloud.r-project.org"))

# devtools 및 remotes 설치
if (!require("remotes")) install.packages("remotes")

# OHDSI 라이브러리 설치
message("Installing OHDSI dependencies...")
if (!require("SqlRender")) install.packages("SqlRender")
if (!require("DatabaseConnector")) install.packages("DatabaseConnector")

# Achilles 설치
message("Installing Achilles...")
remotes::install_github("OHDSI/Achilles")

# 설치 확인
if (require("Achilles")) {
    message("Achilles 설치가 성공적으로 완료되었습니다.")
} else {
    stop("Achilles 설치 실패")
}
EOF

echo "--- 모든 프로세스가 완료되었습니다! ---"
