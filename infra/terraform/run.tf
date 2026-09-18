# Identity the API runs as. Nothing else uses it.
resource "google_service_account" "api" {
  account_id   = "supermortgage-app-api"
  display_name = "Supermortgage API runtime"
}

# Lets the runtime connect through the Cloud SQL volume mount.
resource "google_project_iam_member" "api_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# Lets the Admin SDK verify and revoke tokens, look up and create users, and mint custom tokens.
resource "google_project_iam_member" "api_firebaseauth_admin" {
  project = var.project_id
  role    = "roles/firebaseauth.admin"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# Read access to exactly the secrets the service references, not to Secret Manager as a whole.
resource "google_secret_manager_secret_iam_member" "api_secrets" {
  for_each = {
    database-url      = google_secret_manager_secret.database_url.secret_id
    email-api-key     = google_secret_manager_secret.email_api_key.secret_id
    email-code-pepper = google_secret_manager_secret.email_code_pepper.secret_id
  }

  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

# §4.3: custom tokens on Cloud Run are signed through the IAM API, which needs the runtime
# account to hold Token Creator on itself.
resource "google_service_account_iam_member" "api_token_creator_self" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.api.email}"
}

# The API. Terraform owns the shape of the service; api.yml owns the image
# (`gcloud run deploy --no-traffic`, /health on the new revision, then the traffic shift),
# hence the ignore_changes below. The placeholder image serves 200 on every path, so the
# startup probe passes until the first real deploy.
resource "google_cloud_run_v2_service" "api" {
  name     = "supermortgage-app-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" # only the load balancer in lb.tf reaches it

  # The provider's default, stated: `terraform destroy` needs this flipped to false first.
  deletion_protection = true

  template {
    service_account = google_service_account.api.email

    scaling {
      min_instance_count = var.run_min_instances
      max_instance_count = var.run_max_instances
    }

    # Direct VPC egress: private-range traffic (the Cloud SQL private IP) leaves through the
    # VPC subnet; everything else takes the normal internet path.
    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"

      network_interfaces {
        network    = google_compute_network.vpc.id
        subnetwork = google_compute_subnetwork.run.id
      }
    }

    # The Cloud SQL connector's unix socket, /cloudsql/<connection name>, which DATABASE_URL names.
    volumes {
      name = "cloudsql"

      cloud_sql_instance {
        instances = [google_sql_database_instance.db.connection_name]
      }
    }

    containers {
      name  = "api"
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = var.run_memory
        }
      }

      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }

      env {
        name  = "MAIL_FROM"
        value = var.mail_from
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "EMAIL_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.email_api_key.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "EMAIL_CODE_PEPPER"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.email_code_pepper.secret_id
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      # Migrations run at container start (§4.3), so give a new instance up to three minutes.
      startup_probe {
        initial_delay_seconds = 0
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 18

        http_get {
          path = "/health"
          port = 8080
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image, # api.yml deploys the real image
      client,                          # gcloud stamps its own client name and version
      client_version,
      template[0].labels, # and its own labels and annotations on each revision
      template[0].annotations,
      traffic, # api.yml pins traffic to the revision it verified; Terraform must not move it back to LATEST
    ]
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.api_cloudsql_client,
    google_secret_manager_secret_iam_member.api_secrets,
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_version.email_code_pepper,
    # No dependency on an email-api-key version on purpose: Terraform never creates one (§8).
  ]
}

# Public invocation. Ingress is restricted to the load balancer above, Cloud Armor sits in
# front of that, and the API checks its own Bearer tokens, so no IAM gate is wanted here.
resource "google_cloud_run_v2_service_iam_member" "api_public_invoker" {
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
