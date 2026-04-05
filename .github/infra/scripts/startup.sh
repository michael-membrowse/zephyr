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

# Run the GitHub Actions runner as the runner user
cd /opt/actions-runner
sudo -u runner ./run.sh --jitconfig "${JIT_CONFIG}" || true
