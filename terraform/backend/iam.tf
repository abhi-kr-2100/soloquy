# ──────────────────────────────────────────────
#  Dynamic group — matches the A1 instance
# ──────────────────────────────────────────────

resource "oci_identity_dynamic_group" "backend" {
  compartment_id = var.tenancy_ocid
  name           = "soloquy-backend-dg"
  description    = "Dynamic group for the Soloquy backend A1 instance"
  matching_rule  = "instance.id = '${oci_core_instance.backend.id}'"
}

# ──────────────────────────────────────────────
#  Policy — instance principal can pull images
# ──────────────────────────────────────────────

resource "oci_identity_policy" "backend_pull" {
  compartment_id = var.tenancy_ocid
  name           = "soloquy-backend-pull-policy"
  description    = "Allow the backend VM to pull container images from OCIR"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.backend.name} to read repos in tenancy",
  ]
}
