#!/bin/bash
set -euo pipefail

# Ensure cleanup runs even if startup fails (prevents VM leaks)
trap '/opt/scripts/cleanup.sh' EXIT

METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
METADATA_HEADER="Metadata-Flavor: Google"

# Retry metadata fetch in case network isn't ready at boot
for i in 1 2 3 4 5; do
  JIT_CONFIG=$(curl -sf -H "${METADATA_HEADER}" "${METADATA_URL}/instance/attributes/jit-config") && break
  echo "Metadata fetch attempt $i failed, retrying in 10s..."
  sleep 10
done

if [ -z "${JIT_CONFIG:-}" ]; then
  echo "ERROR: Failed to fetch JIT config after 5 attempts"
  exit 1
fi

CCACHE_BUCKET=$(curl -sf -H "${METADATA_HEADER}" "${METADATA_URL}/instance/attributes/ccache-bucket" || echo "")
export CCACHE_BUCKET

# Auto-update runner if needed
LATEST_VER=$(curl -sf https://api.github.com/repos/actions/runner/releases/latest | grep -oP '"tag_name":\s*"v\K[^"]+')
CURRENT_VER=$(cat /opt/actions-runner/bin/Runner.Listener.deps.json 2>/dev/null | grep -oP '"version":\s*"\K[^"]+' | head -1 || echo "0")
if [ "$LATEST_VER" != "$CURRENT_VER" ]; then
  echo "Updating runner from $CURRENT_VER to $LATEST_VER..."
  cd /opt/actions-runner
  curl -fsSL -o runner.tar.gz "https://github.com/actions/runner/releases/download/v${LATEST_VER}/actions-runner-linux-x64-${LATEST_VER}.tar.gz"
  tar xzf runner.tar.gz
  rm runner.tar.gz
  chown -R runner:runner /opt/actions-runner
fi

# Run the GitHub Actions runner as the runner user
cd /opt/actions-runner
sudo -u runner ./run.sh --jitconfig "${JIT_CONFIG}" || true
