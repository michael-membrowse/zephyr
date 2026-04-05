#!/bin/bash
set -euo pipefail

RUNNER_VERSION="2.322.0"
RUNNER_ARCH="linux-x64"

echo "Installing GitHub Actions runner v${RUNNER_VERSION}..."
mkdir -p /opt/actions-runner
cd /opt/actions-runner

curl -fsSL -o runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
tar xzf runner.tar.gz
rm runner.tar.gz

# Install runner dependencies
./bin/installdependencies.sh

# Create runner user
useradd -m -s /bin/bash runner
usermod -aG docker runner
chown -R runner:runner /opt/actions-runner

echo "Runner installed at /opt/actions-runner"
