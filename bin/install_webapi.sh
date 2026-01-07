sudo apt install -y openjdk-11-jdk 
# Tomcat 9 (WebAPI 호스팅용)
sudo apt install -y tomcat10 tomcat10-admin

sudo apt install -y postgresql-contrib
# Node.js & NPM (ATLAS 빌드용)
sudo apt install -y nodejs npm gettext-base


# Web API Release 다운로드
wget https://github.com/OHDSI/WebAPI/releases/download/v2.15.1/WebAPI.war

sudo cp WebAPI.war /var/lib/tomcat10/webapps/

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
TARGET_FILE="/usr/share/tomcat10/bin/setenv.sh"

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
sudo systemctl restart tomcat10
