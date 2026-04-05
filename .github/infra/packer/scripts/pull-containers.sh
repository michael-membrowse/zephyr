#!/bin/bash
set -euo pipefail

echo "Installing Docker..."
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

systemctl enable docker
systemctl start docker

echo "Pre-pulling container images..."
# Must match the case statement in membrowse-onboard.yml build_script
IMAGES=(
  "ghcr.io/zephyrproject-rtos/ci-repo-cache:v0.29.1.20260327"
  "ghcr.io/zephyrproject-rtos/ci-repo-cache:v0.29.0.20260314"
  "ghcr.io/zephyrproject-rtos/ci-repo-cache:v0.28.7.20251127"
  "ghcr.io/zephyrproject-rtos/ci-repo-cache:v0.28.1.20250624"
  "ghcr.io/zephyrproject-rtos/ci-repo-cache:v0.28.0.20250523"
  "ghcr.io/zephyrproject-rtos/ci-repo-cache:v0.27.4.20241026"
  "ghcr.io/zephyrproject-rtos/ci-repo-cache:v0.26.14.20240823"
  "ghcr.io/zephyrproject-rtos/ci-repo-cache:v0.26.9.20240223"
)

for img in "${IMAGES[@]}"; do
  echo "Pulling ${img}..."
  docker pull "${img}"
done

echo "All container images pulled."
docker images | grep ci-repo-cache
