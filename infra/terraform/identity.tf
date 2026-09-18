# Identity Platform project configuration. Creating this resource also initializes Identity
# Platform on the project; if the apply fails here, Doug has not yet clicked Enable on
# Identity Platform in the Marketplace and accepted the terms (§1.2).
#
# Not expressible here: e-mail enumeration protection (§1.4) has no field in the provider,
# so it stays a console step. The Apple provider (§1.4) is also configured by hand because
# its private key is a paste.
resource "google_identity_platform_config" "default" {
  project            = var.project_id
  authorized_domains = var.authorized_domains

  # Neither Email/Password nor Anonymous: the e-mail door is our own code exchanged for a
  # custom token, and Apple and Google are OAuth providers.
  sign_in {
    email {
      enabled = false
    }
    anonymous {
      enabled = false
    }
  }

  # Sign-up stays open; every door creates the account on first use.
  client {
    permissions {
      disabled_user_signup = false
    }
  }

  depends_on = [google_project_service.apis]
}

# The Google sign-in provider. Its OAuth web client is created by the console when Google is
# added under Providers (§1.4); pass that client's id and secret as variables to bring the
# provider under Terraform. Until then the resource is not created and the console's
# configuration stands.
resource "google_identity_platform_default_supported_idp_config" "google" {
  count = var.google_oauth_client_id == "" ? 0 : 1

  idp_id        = "google.com"
  enabled       = true
  client_id     = var.google_oauth_client_id
  client_secret = var.google_oauth_client_secret

  depends_on = [google_identity_platform_config.default]
}
