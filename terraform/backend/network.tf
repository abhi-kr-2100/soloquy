resource "oci_core_vcn" "this" {
  compartment_id = oci_identity_compartment.soloquy_backend.id
  display_name   = "soloquy-backend-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = oci_identity_compartment.soloquy_backend.id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "soloquy-backend-igw"
  enabled        = true
}

resource "oci_core_route_table" "this" {
  compartment_id = oci_identity_compartment.soloquy_backend.id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "soloquy-backend-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_default_route_table" "this" {
  manage_default_resource_id = oci_core_vcn.this.default_route_table_id
  display_name               = "soloquy-backend-default-rt"
}
