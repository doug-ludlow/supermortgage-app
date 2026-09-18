# Password of the API's database user. Alphanumeric only, so it needs no escaping in a URL;
# secrets.tf still URL-encodes it when building DATABASE_URL.
resource "random_password" "db" {
  length  = 32
  special = false
}

# Postgres 16 on Cloud SQL, private IP only, backed up daily with point-in-time recovery.
# Two deletion guards: Terraform's (deletion_protection) and Cloud SQL's own
# (deletion_protection_enabled), which also stops gcloud and the console. Flip both to false
# and apply before a deliberate teardown.
resource "google_sql_database_instance" "db" {
  name                = "supermortgage-app-db"
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = true

  settings {
    tier                        = var.db_tier
    deletion_protection_enabled = true

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }
  }

  # The private IP needs the peering to exist first; the instance never references it.
  depends_on = [google_service_networking_connection.private_services]
}

# The application database. Migrations run at container start (§4.3).
resource "google_sql_database" "app" {
  name     = "app"
  instance = google_sql_database_instance.db.name
}

# The user the API connects as. The password is also stored in Secret Manager (secrets.tf).
resource "google_sql_user" "api" {
  name     = "api"
  instance = google_sql_database_instance.db.name
  password = random_password.db.result
}
