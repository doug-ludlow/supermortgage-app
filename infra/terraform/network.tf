# The VPC Cloud SQL's private IP lives behind. Cloud Run reaches it through Direct VPC egress
# (see run.tf), so there is no Serverless VPC Access connector.
resource "google_compute_network" "vpc" {
  name                    = "supermortgage-app"
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

# Subnet the Cloud Run instances take their VPC addresses from (one address per instance,
# so a /24 leaves ample room for run_max_instances and rollovers).
resource "google_compute_subnetwork" "run" {
  name                     = "supermortgage-app-run"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.8.0.0/24"
  private_ip_google_access = true
}

# Address range reserved for Google's service-producer network; Cloud SQL's private IP is
# allocated from it.
resource "google_compute_global_address" "private_services" {
  name          = "supermortgage-app-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

# The VPC peering to Google's managed services (private services access). Cloud SQL sits on
# the far side; sql.tf depends on this explicitly because the instance does not reference it.
resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}
