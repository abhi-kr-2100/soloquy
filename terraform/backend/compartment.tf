resource "oci_identity_compartment" "soloquy_backend" {
  name           = "soloquy-backend"
  description    = "Isolates all Soloquy backend resources for easy teardown."
  compartment_id = var.tenancy_ocid
}
