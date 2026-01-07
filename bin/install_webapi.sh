sudo apt install -y openjdk-11-jdk 

sudo apt install -y postgresql-contrib
# Node.js & NPM (ATLAS 빌드용)
sudo apt install -y nodejs npm gettext-base

# tomcat 8.5 최신 버전 다운로드
wget https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.100/bin/apache-tomcat-8.5.100.tar.gz
sudo mkdir -p /opt/tomcat8
sudo tar xzvf apache-tomcat-8.5.100.tar.gz -C /opt/tomcat8 --strip-components=1

rm apache-tomcat-8.5.100.tar.gz

# tomcat 8 서비스 등록
sudo cp config/tomcat8.service /etc/systemd/system/tomcat8.service
sudo systemctl daemon-reload
sudo systemctl enable tomcat8
sudo systemctl start tomcat8

# Web API Release 다운로드
wget https://github.com/OHDSI/WebAPI/releases/download/v2.15.1/WebAPI.war
sudo mv WebAPI.war /opt/tomcat8/webapps/

# ----------------------------------------------------------------
# Tomcat setenv.sh 설정 (WebAPI 환경변수 적용)
# ----------------------------------------------------------------
# .env 파일 로드 (스크립트 실행 위치 기준)
set -a
if [ -f ".env" ]; then
    source .env
else
    echo "Error: .env file not found."
    exit 1
fi
set +a

# 템플릿 파일 경로
TEMPLATE_FILE="config/webapi_setenv.sh"
TARGET_FILE="/opt/tomcat8/bin/setenv.sh"

if [ ! -f "$TEMPLATE_FILE" ]; then
   echo "Error: Configuration template $TEMPLATE_FILE not found."
   exit 1
fi

echo "Generating $TARGET_FILE from $TEMPLATE_FILE..."

# 필요한 변수들만 envsubst에 전달하여 치환 (안전성 확보)
EXISTING_VARS='$POSTGRES_SERVER $POSTGRES_PORT $POSTGRES_DB $POSTGRES_USER $POSTGRES_PASSWORD'

# envsubst를 사용하여 환경변수 치환 후 setenv.sh 생성
envsubst "$EXISTING_VARS" < "$TEMPLATE_FILE" | sudo tee "$TARGET_FILE" > /dev/null

sudo chmod +x "$TARGET_FILE"
sudo chown tomcat:tomcat "$TARGET_FILE"

echo "Tomcat configuration updated."
sudo systemctl restart tomcat8
