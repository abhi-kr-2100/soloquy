resource "oci_core_subnet" "this" {
  compartment_id = oci_identity_compartment.soloquy_backend.id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "soloquy-backend-subnet"

  cidr_block        = "10.0.0.0/24"
  route_table_id    = oci_core_route_table.this.id
  security_list_ids = [oci_core_security_list.this.id]

  # Public IPs are assigned via the reserved oci_core_public_ip resource
  # (created with the instance in 3.3.6), so no automatic public assignment here.
  prohibit_public_ip_on_vnic = false
}
