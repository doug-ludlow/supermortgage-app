# Terraform and provider pins for the Supermortgage cloud environment.
# One root module, applied once per GCP project (supermortgage-app-nonprod now, -prod later).
terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    # Declared next to google so a beta-only field can be adopted without a provider change.
    # Nothing in this module uses it today: every resource here is GA in the google provider.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # The bucket is deliberately absent: bootstrap.sh creates <project>-tfstate and prints the
  # `terraform init -backend-config="bucket=..."` line that supplies it.
  backend "gcs" {
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}
