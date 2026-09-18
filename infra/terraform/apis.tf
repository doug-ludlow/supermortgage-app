# APIs the environment needs, per §5 of docs/SIGNUP-FOR-REAL.md. Left enabled on destroy so
# removing one resource from Terraform never switches an API off under the others.
locals {
  services = [
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "identitytoolkit.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "compute.googleapis.com",
    "certificatemanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "vpcaccess.googleapis.com",
    # Not in the §5 list: the Security Token Service is what GitHub's OIDC token is exchanged
    # against for Workload Identity Federation, and Google's WIF setup guide enables it.
    "sts.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.services)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
