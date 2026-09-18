# Docker repository the API images are pushed to by api.yml
# (<region>-docker.pkg.dev/<project>/api/<image>).
resource "google_artifact_registry_repository" "api" {
  location      = var.region
  repository_id = "api"
  format        = "DOCKER"
  description   = "Supermortgage API container images"

  depends_on = [google_project_service.apis]
}
