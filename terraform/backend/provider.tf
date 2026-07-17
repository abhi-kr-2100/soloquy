# ──────────────────────────────────────────────
#  OCI Provider — authenticates via API key
# ──────────────────────────────────────────────

provider "oci" {
  tenancy_ocid         = var.tenancy_ocid
  user_ocid            = var.user_ocid
  fingerprint          = var.fingerprint
  private_key          = var.private_key
  private_key_password = var.private_key_pass_phrase
  region               = var.region
}
