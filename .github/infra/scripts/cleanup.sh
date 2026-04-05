#!/bin/bash
# VM deletion is handled by the Cloud Function on the 'completed' webhook.
# This script runs as a safety net via the EXIT trap in startup.sh.
echo "Runner finished. VM will be deleted by the webhook handler."
