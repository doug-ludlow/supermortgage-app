output "load_balancer_ip" {
  description = "Public IPv4 address of the load balancer."
  value       = google_compute_global_address.lb.address
}

output "dns_line" {
  description = "The record to create at GoDaddy (§1.8)."
  value       = "A record: ${var.api_domain} → ${google_compute_global_address.lb.address}"
}

output "cloud_run_service" {
  description = "Name of the Cloud Run service api.yml deploys to."
  value       = google_cloud_run_v2_service.api.name
}

output "cloud_run_uri" {
  description = "The service's run.app URL (ingress only admits the load balancer, so it answers 404 directly)."
  value       = google_cloud_run_v2_service.api.uri
}

output "artifact_registry" {
  description = "Docker repository api.yml pushes to."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.api.repository_id}"
}

output "workload_identity_provider" {
  description = "Full name of the WIF provider; the GitHub repository variable GCP_WIF_PROVIDER."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "deploy_service_account" {
  description = "E-mail of the deploy account; the GitHub repository variable GCP_DEPLOY_SA."
  value       = google_service_account.deploy.email
}

output "runtime_service_account" {
  description = "E-mail of the account the API runs as."
  value       = google_service_account.api.email
}

output "sql_connection_name" {
  description = "Cloud SQL connection name (project:region:instance), the /cloudsql socket directory."
  value       = google_sql_database_instance.db.connection_name
}
