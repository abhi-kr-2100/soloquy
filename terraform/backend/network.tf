# ──────────────────────────────────────────────
#  VCN
# ──────────────────────────────────────────────

resource "oci_core_vcn" "backend" {
  compartment_id = local.compartment_id
  display_name   = "soloquy-backend-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "sqbackend"
}

# ──────────────────────────────────────────────
#  Internet gateway
# ──────────────────────────────────────────────

resource "oci_core_internet_gateway" "backend" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.backend.id
  display_name   = "soloquy-backend-igw"
  enabled        = true
}

# ──────────────────────────────────────────────
#  Route table — default route via IGW
# ──────────────────────────────────────────────

resource "oci_core_route_table" "backend" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.backend.id
  display_name   = "soloquy-backend-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.backend.id
  }
}

# ──────────────────────────────────────────────
#  Security list — ingress 8080, NO SSH (22)
# ──────────────────────────────────────────────

resource "oci_core_security_list" "backend" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.backend.id
  display_name   = "soloquy-backend-sl"

  # ── Ingress: only 8080/tcp from anywhere ──
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    description = "Allow HTTP on port 8080"

    tcp_options {
      min = 8080
      max = 8080
    }
  }

  # ── Egress: allow all outbound (for OCIR pulls, OS updates) ──
  egress_security_rules {
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    description      = "Allow all outbound traffic"
  }
}

# ──────────────────────────────────────────────
#  Reserved public IP — stable address across
#  instance stop/start and re-creation. Free while
#  attached to a running instance.
# ──────────────────────────────────────────────

resource "oci_core_public_ip" "backend" {
  compartment_id = local.compartment_id
  lifetime       = "RESERVED"
  display_name   = "soloquy-backend-ip"
  private_ip_id  = data.oci_core_private_ips.backend.private_ips[0].id
}

data "oci_core_vnic_attachments" "backend" {
  compartment_id = local.compartment_id
  instance_id    = oci_core_instance.backend.id
}

data "oci_core_private_ips" "backend" {
  vnic_id = data.oci_core_vnic_attachments.backend.vnic_attachments[0].vnic_id
}

# ──────────────────────────────────────────────
#  Public subnet
# ──────────────────────────────────────────────

resource "oci_core_subnet" "backend" {
  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.backend.id
  display_name               = "soloquy-backend-subnet"
  cidr_block                 = "10.0.1.0/24"
  dns_label                  = "sqsub"
  route_table_id             = oci_core_route_table.backend.id
  security_list_ids          = [oci_core_security_list.backend.id]
  prohibit_public_ip_on_vnic = false
}
