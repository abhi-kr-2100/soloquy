# ──────────────────────────────────────────────
#  Compartment — isolates all backend resources
# ──────────────────────────────────────────────

resource "oci_identity_compartment" "backend" {
  compartment_id = var.tenancy_ocid
  name           = "soloquy-backend"
  description    = "Soloquy backend compartment"
}
