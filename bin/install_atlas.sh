wget https://github.com/OHDSI/Atlas/releases/download/v2.15.0/atlas.zip

unzip -d atlas ./atlas.zip

sudo mkdir -p /var/www/html

rm -rf /var/www/html/atlas

sudo mv atlas/atlas /var/www/html

sudo chown -R $USER:$USER /var/www/html/atlas

# Configure atlas_config-local.js
echo "Generating config-local.js..."
PROJECT_ROOT="$(dirname "$0")/.."
ENV_FILE="$PROJECT_ROOT/.env"
CONFIG_TEMPLATE="$PROJECT_ROOT/config/atlas_config-local.js"
TARGET_CONFIG="/var/www/html/atlas/js/config-local.js"

if [ -f "$ENV_FILE" ]; then
  # Load .env variables
  set -a
  source "$ENV_FILE"
  set +a
fi

if [ -f "$CONFIG_TEMPLATE" ]; then
  if [ -z "$ATLAS_SERVER_HOST" ]; then
    echo "Warning: ATLAS_SERVER_HOST is not set in .env."
  fi
  # Replace variable and write to target
  sed "s|\$ATLAS_SERVER_HOST|${ATLAS_SERVER_HOST}|g" "$CONFIG_TEMPLATE" | sudo tee "$TARGET_CONFIG" > /dev/null
  echo "Config file created at $TARGET_CONFIG"
else
  echo "Error: Config template not found at $CONFIG_TEMPLATE"
fi

rm atlas.zip
rmdir atlas



