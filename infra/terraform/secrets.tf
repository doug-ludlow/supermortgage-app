# Everything the API reads from Secret Manager. The Cloud Run service (run.tf) references
# database-url, email-api-key and email-code-pepper by name at version "latest".
locals {
  # The unix-socket form node-postgres accepts through Cloud Run's Cloud SQL volume mount.
  database_url = "postgresql://${google_sql_user.api.name}:${urlencode(random_password.db.result)}@/${google_sql_database.app.name}?host=/cloudsql/${google_sql_database_instance.db.connection_name}"
}

# The database user's password on its own, for humans and psql; the API uses database-url.
resource "google_secret_manager_secret" "db_password" {
  secret_id = "db-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}

# The full connection string the API reads as DATABASE_URL.
resource "google_secret_manager_secret" "database_url" {
  secret_id = "database-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = local.database_url
}

# Pepper mixed into the sign-in code hashes (§4.2: sha256(pepper + email + code)).
resource "random_password" "email_code_pepper" {
  length  = 48
  special = false
}

resource "google_secret_manager_secret" "email_code_pepper" {
  secret_id = "email-code-pepper"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "email_code_pepper" {
  secret      = google_secret_manager_secret.email_code_pepper.id
  secret_data = random_password.email_code_pepper.result
}

# The transactional e-mail API key (§1.7). Terraform creates the secret but never a version:
# Doug adds the value by hand (see infra/README.md). Cloud Run refuses to start a revision
# whose secret has no version, so the version must exist before the service is first applied.
resource "google_secret_manager_secret" "email_api_key" {
  secret_id = "email-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}
