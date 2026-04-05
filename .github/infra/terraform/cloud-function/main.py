"""Cloud Function webhook handler for GitHub Actions self-hosted runners.

Listens for workflow_job events and creates/deletes GCE spot instances
to serve as ephemeral GitHub Actions runners.
"""

import hashlib
import hmac
import os

import functions_framework
from google.cloud import compute_v1, secretmanager_v1


PROJECT_ID = os.environ["GCP_PROJECT"]
ZONE = os.environ.get("GCE_ZONE", "us-central1-a")
MACHINE_TYPE = os.environ.get("GCE_MACHINE_TYPE", "c2-standard-8")
IMAGE_FAMILY = os.environ.get("GCE_IMAGE_FAMILY", "zephyr-runner")
RUNNER_LABEL = os.environ.get("RUNNER_LABEL", "zephyr-membrowse")
SERVICE_ACCOUNT = os.environ.get(
    "GCE_SERVICE_ACCOUNT", f"zephyr-runner@{PROJECT_ID}.iam.gserviceaccount.com"
)
CCACHE_BUCKET = os.environ.get("CCACHE_BUCKET", f"{PROJECT_ID}-zephyr-ccache")
NETWORK = os.environ.get("GCE_NETWORK", "default")

instances_client = compute_v1.InstancesClient()
images_client = compute_v1.ImagesClient()

_secrets_cache: dict[str, str] = {}


def get_secret(secret_id: str) -> str:
    if secret_id not in _secrets_cache:
        client = secretmanager_v1.SecretManagerServiceClient()
        name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/latest"
        response = client.access_secret_version(request={"name": name})
        _secrets_cache[secret_id] = response.payload.data.decode("utf-8")
    return _secrets_cache[secret_id]


def verify_webhook_signature(request) -> bool:
    signature = request.headers.get("X-Hub-Signature-256", "")
    if not signature.startswith("sha256="):
        return False

    webhook_secret = get_secret("github-webhook-secret")
    expected = hmac.new(
        webhook_secret.encode(), request.get_data(), hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(signature[7:], expected)


def get_jit_runner_config(job_id: int) -> str:
    """Request a JIT runner configuration from GitHub API."""
    import requests

    github_token = get_secret("github-runner-pat")
    repo = os.environ.get("GITHUB_REPO", "michael-membrowse/zephyr")

    resp = requests.post(
        f"https://api.github.com/repos/{repo}/actions/runners/generate-jitconfig",
        headers={
            "Authorization": f"Bearer {github_token}",
            "Accept": "application/vnd.github+json",
        },
        json={
            "name": f"zephyr-runner-{job_id}",
            "runner_group_id": 1,
            "labels": [RUNNER_LABEL],
        },
    )
    resp.raise_for_status()
    return resp.json()["encoded_jit_config"]


def get_latest_image() -> str:
    request = compute_v1.GetFromFamilyImageRequest(
        project=PROJECT_ID, family=IMAGE_FAMILY
    )
    image = images_client.get_from_family(request=request)
    return image.self_link


def create_runner_instance(job_id: int) -> None:
    instance_name = f"zephyr-runner-{job_id}"
    jit_config = get_jit_runner_config(job_id)
    image_link = get_latest_image()

    startup_script = f"""#!/bin/bash
exec > /var/log/runner-startup.log 2>&1
cp /opt/scripts/startup.sh /tmp/startup.sh
chmod +x /tmp/startup.sh
/tmp/startup.sh
"""

    instance = compute_v1.Instance(
        name=instance_name,
        machine_type=f"zones/{ZONE}/machineTypes/{MACHINE_TYPE}",
        disks=[
            compute_v1.AttachedDisk(
                boot=True,
                auto_delete=True,
                initialize_params=compute_v1.AttachedDiskInitializeParams(
                    source_image=image_link,
                    disk_size_gb=500,
                    disk_type=f"zones/{ZONE}/diskTypes/pd-ssd",
                ),
            )
        ],
        network_interfaces=[
            compute_v1.NetworkInterface(
                network=f"global/networks/{NETWORK}",
                access_configs=[
                    compute_v1.AccessConfig(
                        name="External NAT",
                        type_="ONE_TO_ONE_NAT",
                    )
                ],
            )
        ],
        service_accounts=[
            compute_v1.ServiceAccount(
                email=SERVICE_ACCOUNT,
                scopes=["https://www.googleapis.com/auth/cloud-platform"],
            )
        ],
        metadata=compute_v1.Metadata(
            items=[
                compute_v1.Items(key="startup-script", value=startup_script),
                compute_v1.Items(key="jit-config", value=jit_config),
                compute_v1.Items(key="ccache-bucket", value=CCACHE_BUCKET),
            ]
        ),
        scheduling=compute_v1.Scheduling(
            provisioning_model="SPOT",
            instance_termination_action="DELETE",
            on_host_maintenance="TERMINATE",
            automatic_restart=False,
        ),
        labels={
            "purpose": "github-runner",
            "workflow": "membrowse-onboard",
        },
    )

    request = compute_v1.InsertInstanceRequest(
        project=PROJECT_ID, zone=ZONE, instance_resource=instance
    )
    operation = instances_client.insert(request=request)
    print(f"Creating instance {instance_name}: {operation.name}")


def delete_runner_instance(job_id: int) -> None:
    instance_name = f"zephyr-runner-{job_id}"
    try:
        request = compute_v1.DeleteInstanceRequest(
            project=PROJECT_ID, zone=ZONE, instance=instance_name
        )
        operation = instances_client.delete(request=request)
        print(f"Deleting instance {instance_name}: {operation.name}")
    except Exception as e:
        # Instance may already be self-deleted
        print(f"Could not delete {instance_name} (may already be gone): {e}")


@functions_framework.http
def handle_webhook(request):
    if not verify_webhook_signature(request):
        return "Invalid signature", 403

    event_type = request.headers.get("X-GitHub-Event")
    if event_type != "workflow_job":
        return "Not a workflow_job event", 200

    payload = request.get_json()
    action = payload.get("action")
    job = payload.get("workflow_job", {})
    job_id = job.get("id")
    labels = job.get("labels", [])

    if RUNNER_LABEL not in labels:
        return "Not our runner label", 200

    if action == "queued":
        print(f"Job {job_id} queued, creating runner instance...")
        create_runner_instance(job_id)
        return "Runner instance creation initiated", 200

    elif action == "completed":
        print(f"Job {job_id} completed, cleaning up runner instance...")
        delete_runner_instance(job_id)
        return "Runner instance deletion initiated", 200

    return f"Unhandled action: {action}", 200
