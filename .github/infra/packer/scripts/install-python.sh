#!/bin/bash
set -euo pipefail

echo "Installing Python 3.12..."
apt-get update
apt-get install -y software-properties-common
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update
apt-get install -y python3.12 python3.12-venv python3.12-dev

echo "Creating virtualenv with requirements..."
python3.12 -m venv /opt/venv
/opt/venv/bin/pip install --upgrade pip

# requirements-actions.txt will be copied from the repo at build time
# For now, create a marker script that installs on first boot if needed
cat > /opt/install-requirements.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
REPO_DIR="$1"
REQ_FILE="${REPO_DIR}/scripts/requirements-actions.txt"
HASH_FILE="/opt/venv/.requirements-hash"

if [ ! -f "$REQ_FILE" ]; then
  echo "No requirements file found at ${REQ_FILE}, skipping"
  exit 0
fi

CURRENT_HASH=$(sha256sum "$REQ_FILE" | cut -d' ' -f1)
if [ -f "$HASH_FILE" ] && [ "$(cat "$HASH_FILE")" = "$CURRENT_HASH" ]; then
  echo "Requirements already up to date"
  exit 0
fi

echo "Installing Python requirements..."
/opt/venv/bin/pip install -r "$REQ_FILE" --require-hashes
echo "$CURRENT_HASH" > "$HASH_FILE"
SCRIPT
chmod +x /opt/install-requirements.sh

echo "Installing zstd and gsutil dependencies..."
apt-get install -y zstd
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list
apt-get update
apt-get install -y google-cloud-cli
