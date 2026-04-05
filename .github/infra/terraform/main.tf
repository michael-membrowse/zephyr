terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# --- Enable APIs ---

resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# --- Service Account for runner VMs ---

resource "google_service_account" "runner" {
  account_id   = "zephyr-runner"
  display_name = "Zephyr GitHub Actions Runner"
}

resource "google_project_iam_member" "runner_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.runner.email}"
}

# --- GCS bucket for ccache ---

resource "google_storage_bucket" "ccache" {
  name     = "${var.project_id}-zephyr-ccache"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket_iam_member" "runner_ccache" {
  bucket = google_storage_bucket.ccache.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.runner.email}"
}

# --- Secret Manager ---

resource "google_secret_manager_secret" "github_runner_pat" {
  secret_id = "github-runner-pat"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "github_webhook_secret" {
  secret_id = "github-webhook-secret"
  replication {
    auto {}
  }
}

# Cloud Function service account needs access to secrets
resource "google_service_account" "cloud_function" {
  account_id   = "zephyr-webhook-handler"
  display_name = "Zephyr Webhook Handler"
}

resource "google_secret_manager_secret_iam_member" "cf_pat_access" {
  secret_id = google_secret_manager_secret.github_runner_pat.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_function.email}"
}

resource "google_secret_manager_secret_iam_member" "cf_webhook_access" {
  secret_id = google_secret_manager_secret.github_webhook_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_function.email}"
}

# Cloud Function needs to create/delete VMs
resource "google_project_iam_member" "cf_compute" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.cloud_function.email}"
}

resource "google_project_iam_member" "cf_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloud_function.email}"
}

# --- Cloud Function ---

resource "google_storage_bucket" "cf_source" {
  name     = "${var.project_id}-cf-source"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}

data "archive_file" "cloud_function" {
  type        = "zip"
  source_dir  = "${path.module}/cloud-function"
  output_path = "${path.module}/.build/cloud-function.zip"
}

resource "google_storage_bucket_object" "cf_source" {
  name   = "cloud-function-${data.archive_file.cloud_function.output_md5}.zip"
  bucket = google_storage_bucket.cf_source.name
  source = data.archive_file.cloud_function.output_path
}

resource "google_cloudfunctions2_function" "webhook" {
  name     = "zephyr-runner-webhook"
  location = var.region

  build_config {
    runtime     = "python312"
    entry_point = "handle_webhook"
    source {
      storage_source {
        bucket = google_storage_bucket.cf_source.name
        object = google_storage_bucket_object.cf_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 5
    min_instance_count    = 0
    timeout_seconds       = 120
    service_account_email = google_service_account.cloud_function.email

    environment_variables = {
      GCP_PROJECT      = var.project_id
      GCE_ZONE         = var.zone
      GCE_MACHINE_TYPE = "c2-standard-8"
      GCE_IMAGE_FAMILY = "zephyr-runner"
      RUNNER_LABEL     = "zephyr-membrowse"
      CCACHE_BUCKET    = google_storage_bucket.ccache.name
      GITHUB_REPO      = var.github_repo
    }
  }

  depends_on = [google_project_service.apis["cloudfunctions.googleapis.com"]]
}

# Allow unauthenticated invocations (GitHub webhooks)
resource "google_cloud_run_v2_service_iam_member" "webhook_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.webhook.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
