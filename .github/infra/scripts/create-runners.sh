#!/bin/bash
set -euo pipefail

# Creates GCE runner VMs for all queued workflow jobs.
# Usage: ./create-runners.sh [run_id] [max_vms]
#   If run_id is omitted, uses the latest workflow run.
#   max_vms defaults to 10.

PROJECT_ID="membrowse"
ZONE="us-central1-a"
MACHINE_TYPE="n2-standard-8"
IMAGE_FAMILY="zephyr-runner"
SERVICE_ACCOUNT="zephyr-runner@${PROJECT_ID}.iam.gserviceaccount.com"
CCACHE_BUCKET="${PROJECT_ID}-zephyr-ccache"
REPO="michael-membrowse/zephyr"
RUNNER_LABEL="zephyr-membrowse"

MAX_VMS="${2:-10}"
RUN_ID="${1:-}"
if [ -z "$RUN_ID" ]; then
  RUN_ID=$(gh run list --repo "$REPO" --limit 1 --json databaseId -q '.[].databaseId')
  echo "Using latest run: $RUN_ID"
fi

# Wait for jobs to be queued
echo "Waiting for jobs to appear..."
for i in $(seq 1 30); do
  JOBS=$(gh api "repos/${REPO}/actions/runs/${RUN_ID}/jobs" --jq '.jobs[] | select(.status == "queued") | .id' 2>/dev/null)
  if [ -n "$JOBS" ]; then
    break
  fi
  sleep 5
done

if [ -z "$JOBS" ]; then
  echo "No queued jobs found for run $RUN_ID"
  exit 1
fi

JOB_COUNT=$(echo "$JOBS" | wc -l)
echo "Found $JOB_COUNT queued jobs. Creating up to $MAX_VMS runner VMs..."

COUNT=0
for JOB_ID in $JOBS; do
  COUNT=$((COUNT + 1))
  if [ $COUNT -gt $MAX_VMS ]; then break; fi
  INSTANCE_NAME="zephyr-runner-${JOB_ID}"

  # Request JIT runner config from GitHub
  JIT_CONFIG=$(gh api "repos/${REPO}/actions/runners/generate-jitconfig" \
    --method POST \
    --field "name=${INSTANCE_NAME}" \
    --field "runner_group_id=1" \
    --field 'labels[]=self-hosted' \
    --field 'labels[]=zephyr-membrowse' \
    --jq '.encoded_jit_config')

  # Create the VM
  gcloud compute instances create "$INSTANCE_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --image-family="$IMAGE_FAMILY" \
    --image-project="$PROJECT_ID" \
    --boot-disk-size=300GB \
    --boot-disk-type=pd-standard \
    --service-account="$SERVICE_ACCOUNT" \
    --scopes=cloud-platform \
    --no-restart-on-failure \
    --metadata="jit-config=${JIT_CONFIG},ccache-bucket=${CCACHE_BUCKET}" \
    --metadata-from-file=startup-script="$(dirname "$0")/startup.sh" \
    --async \
    --quiet &

  echo "  [$COUNT/$MAX_VMS] Creating $INSTANCE_NAME"
done

wait
echo "Done. $COUNT runner VMs created."
