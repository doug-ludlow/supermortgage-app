variable "project_id" {
  description = "GCP project that holds this environment (one project per environment)."
  type        = string
}

variable "region" {
  description = "Region for Cloud Run, Cloud SQL, Artifact Registry and the VPC subnet."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name; the API receives it as ENVIRONMENT."
  type        = string
  default     = "nonprod"
}

variable "api_domain" {
  description = "Public hostname of the API. The managed certificate and the DNS line use it."
  type        = string
  default     = "api-nonprod.supermortgage.com"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) whose Actions may deploy through Workload Identity Federation."
  type        = string
  default     = "doug-ludlow/supermortgage-app"
}

variable "mail_from" {
  description = "From header of the sign-in code e-mails; the API receives it as MAIL_FROM."
  type        = string
  default     = "Supermortgage <code@mail.supermortgage.com>"
}

variable "db_tier" {
  description = "Cloud SQL machine tier."
  type        = string
  default     = "db-g1-small"
}

variable "run_min_instances" {
  description = "Minimum number of Cloud Run instances kept warm."
  type        = number
  default     = 1
}

variable "run_max_instances" {
  description = "Maximum number of Cloud Run instances."
  type        = number
  default     = 10
}

variable "run_memory" {
  description = "Memory limit of the API container."
  type        = string
  default     = "512Mi"
}

variable "authorized_domains" {
  description = "Domains Identity Platform accepts for OAuth redirects."
  type        = list(string)
  default     = ["supermortgage-app-nonprod.firebaseapp.com", "localhost"]
}

variable "rate_limit_per_minute" {
  description = "Cloud Armor throttle: requests per minute allowed per client IP before a 429."
  type        = number
  default     = 600
}

variable "state_bucket" {
  description = "Name of the GCS bucket holding this module's state (from bootstrap.sh). When set, the deploy service account is granted object access to it so infra.yml can run plan and apply. Empty skips that binding."
  type        = string
  default     = ""
}

variable "google_oauth_client_id" {
  description = "OAuth web client id for the Google sign-in provider, from the client the console auto-creates when Google is added under Identity Platform → Providers (§1.4). Empty leaves the Google provider unmanaged by Terraform."
  type        = string
  default     = ""
}

variable "google_oauth_client_secret" {
  description = "OAuth web client secret matching google_oauth_client_id. Pass it with -var or TF_VAR_google_oauth_client_secret, never in a committed file."
  type        = string
  default     = ""
  sensitive   = true
}
