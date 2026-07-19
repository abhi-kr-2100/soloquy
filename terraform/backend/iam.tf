resource "oci_identity_dynamic_group" "soloquy_backend" {
  compartment_id = var.tenancy_ocid
  name           = "soloquy-backend-instances"
  description    = "Instances in the soloquy-backend compartment (used for OCIR instance-principal pull)."
  matching_rule  = "All {instance.compartment.id = '${oci_identity_compartment.soloquy_backend.id}'}"
}

resource "oci_identity_policy" "soloquy_backend_pull" {
  compartment_id = var.tenancy_ocid
  name           = "soloquy-backend-pull"
  description    = "Allow the soloquy-backend dynamic group to read OCIR repos in the tenancy (instance-principal pull)."
  statements     = ["Allow dynamic-group ${oci_identity_dynamic_group.soloquy_backend.name} to read repos in tenancy"]
}
