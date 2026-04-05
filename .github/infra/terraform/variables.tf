variable "project_id" {
  type        = string
  description = "GCP project ID"
  default     = "membrowse"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository (owner/name)"
  default     = "michael-membrowse/zephyr"
}
