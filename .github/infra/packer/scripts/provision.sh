#!/bin/bash
set -euo pipefail

echo "=== Provisioning Zephyr runner image ==="

# Run sub-scripts in order
for script in ${PROVISION_SCRIPTS:-pull-containers install-python install-runner}; do
  echo "--- Running ${script}.sh ---"
  bash "/tmp/packer-scripts/${script}.sh"
done

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/packer-scripts

echo "=== Provisioning complete ==="
