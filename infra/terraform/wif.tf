# Workload Identity Federation for GitHub Actions: no long-lived keys. api.yml and infra.yml
# authenticate with google-github-actions/auth against the provider below and impersonate
# the deploy service account.

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "OIDC tokens from GitHub Actions for ${var.github_repository}"

  depends_on = [google_project_service.apis]
}

# Trusts GitHub's OIDC issuer, but only tokens minted for our repository.
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# The account GitHub Actions impersonates.
resource "google_service_account" "deploy" {
  account_id   = "github-deploy"
  display_name = "GitHub Actions deploy"
}

# Any workflow of the repository may impersonate the deploy account.
resource "google_service_account_iam_member" "deploy_wif" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# Project roles of the deploy account. The first two are what api.yml needs (§5); the rest
# are what infra.yml needs to plan and apply this module. roles/owner would be too broad;
# roles/editor alone cannot touch IAM, so the admin roles add the IAM policies this module
# sets on the project, on service accounts and on secrets, and the pool admin role covers
# the Workload Identity resources editor lacks. See infra/README.md.
locals {
  deploy_project_roles = [
    "roles/run.admin",                       # api.yml: deploy revisions and shift traffic
    "roles/artifactregistry.writer",         # api.yml: push images
    "roles/editor",                          # infra.yml: create and change the resources here
    "roles/iam.securityAdmin",               # infra.yml: IAM policies on service accounts, secrets, buckets, Cloud Run
    "roles/resourcemanager.projectIamAdmin", # infra.yml: project-level role bindings
    "roles/secretmanager.admin",             # infra.yml: secrets and their IAM
    "roles/iam.workloadIdentityPoolAdmin",   # infra.yml: this pool and provider
  ]
}

resource "google_project_iam_member" "deploy" {
  for_each = toset(local.deploy_project_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Deploying a revision that runs as the runtime account requires acting as it.
resource "google_service_account_iam_member" "deploy_acts_as_api" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deploy.email}"
}

# Read and write the Terraform state in the bootstrap bucket (only when its name is passed).
resource "google_storage_bucket_iam_member" "deploy_state" {
  count = var.state_bucket == "" ? 0 : 1

  bucket = var.state_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.deploy.email}"
}
