# Global external HTTPS load balancer in front of the Cloud Run service:
# forwarding rules (443 and 80) → proxies → URL maps → backend service → serverless NEG → Cloud Run,
# with a managed certificate for var.api_domain and Cloud Armor on the backend service.

# The one public IPv4 address. outputs.tf prints it as the DNS line.
resource "google_compute_global_address" "lb" {
  name         = "supermortgage-app-api"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"

  depends_on = [google_project_service.apis]
}

# Serverless network endpoint group pointing at the Cloud Run service.
resource "google_compute_region_network_endpoint_group" "api" {
  name                  = "supermortgage-app-api"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.api.name
  }
}

# Preconfigured WAF rule sets evaluated in preview (logged, not enforced) until tuned.
locals {
  waf_rule_sets = [
    "sqli-v33-stable",
    "xss-v33-stable",
    "lfi-v33-stable",
    "rce-v33-stable",
    "rfi-v33-stable",
    "scannerdetection-v33-stable",
    "protocolattack-v33-stable",
  ]
}

# Cloud Armor policy: a per-IP throttle that answers 429 above rate_limit_per_minute, the
# preconfigured WAF rules in preview, and the default allow.
resource "google_compute_security_policy" "api" {
  name        = "supermortgage-app-api"
  description = "Rate limit and WAF (preview) for the Supermortgage API"

  rule {
    priority    = 1000
    action      = "throttle"
    description = "Per-IP rate limit"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"

      rate_limit_threshold {
        count        = var.rate_limit_per_minute
        interval_sec = 60
      }
    }
  }

  dynamic "rule" {
    for_each = { for i, s in local.waf_rule_sets : s => i }

    content {
      priority    = 10 + rule.value
      action      = "deny(403)"
      preview     = true
      description = "WAF ${rule.key} (preview)"

      match {
        expr {
          expression = "evaluatePreconfiguredWaf('${rule.key}')"
        }
      }
    }
  }

  rule {
    priority    = 2147483647
    action      = "allow"
    description = "Default allow"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  depends_on = [google_project_service.apis]
}

# Backend service for the serverless NEG (no health check: serverless backends have none).
resource "google_compute_backend_service" "api" {
  name                  = "supermortgage-app-api"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.api.self_link

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }
}

# HTTPS: everything to the backend service.
resource "google_compute_url_map" "https" {
  name            = "supermortgage-app-api"
  default_service = google_compute_backend_service.api.id
}

# HTTP: a 301 to the https URL, query string kept.
resource "google_compute_url_map" "http_redirect" {
  name = "supermortgage-app-api-http-redirect"

  default_url_redirect {
    https_redirect         = true
    strip_query            = false
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
  }
}

# Google-managed certificate for the API hostname. It is only issued once the DNS A record
# points at the load balancer IP; expect up to an hour after that. The name embeds the
# domain so a domain change makes a new certificate before the old one goes.
resource "google_compute_managed_ssl_certificate" "api" {
  name = "api-${replace(var.api_domain, ".", "-")}"

  managed {
    domains = [var.api_domain]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_target_https_proxy" "api" {
  name             = "supermortgage-app-api"
  url_map          = google_compute_url_map.https.id
  ssl_certificates = [google_compute_managed_ssl_certificate.api.id]
}

resource "google_compute_target_http_proxy" "api" {
  name    = "supermortgage-app-api-http"
  url_map = google_compute_url_map.http_redirect.id
}

# Port 443 on the public address.
resource "google_compute_global_forwarding_rule" "https" {
  name                  = "supermortgage-app-api-https"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "443"
  ip_address            = google_compute_global_address.lb.address
  target                = google_compute_target_https_proxy.api.id
}

# Port 80 on the same address, for the redirect.
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "supermortgage-app-api-http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "80"
  ip_address            = google_compute_global_address.lb.address
  target                = google_compute_target_http_proxy.api.id
}
