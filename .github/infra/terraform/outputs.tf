output "webhook_url" {
  description = "URL to configure as the GitHub webhook endpoint"
  value       = google_cloudfunctions2_function.webhook.service_config[0].uri
}

output "ccache_bucket" {
  description = "GCS bucket for ccache storage"
  value       = google_storage_bucket.ccache.name
}

output "service_account_email" {
  description = "Service account for runner VMs"
  value       = google_service_account.runner.email
}
