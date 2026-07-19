resource "oci_artifacts_container_repository" "soloquybackend" {
  compartment_id = oci_identity_compartment.soloquy_backend.id
  display_name   = "soloquybackend"
  is_public      = false
}
