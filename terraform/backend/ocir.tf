# ──────────────────────────────────────────────
#  OCIR container repository
# ──────────────────────────────────────────────

resource "oci_artifacts_container_repository" "backend" {
  compartment_id = local.compartment_id
  display_name   = "soloquybackend"
  is_public      = false
  is_immutable   = true
}
