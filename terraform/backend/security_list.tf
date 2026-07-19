# Adopt OCI's default security list for this VCN so it is managed and cannot
# drift. Its permissive defaults are replaced with deny-by-default rules.
resource "oci_core_default_security_list" "this" {
  manage_default_resource_id = oci_core_vcn.this.default_security_list_id

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "10.0.0.0/16"

    tcp_options {
      min = 8080
      max = 8080
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "10.0.0.0/16"
  }
}

resource "oci_core_security_list" "this" {
  compartment_id = oci_identity_compartment.soloquy_backend.id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "soloquy-backend-sl"

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 8080
      max = 8080
    }
  }

  ingress_security_rules {
    protocol = "1" # ICMP
    source   = "0.0.0.0/0"

    icmp_options {
      type = 3
      code = 4
    }
  }

  # Temporary SSH ingress for the Phase 5 recovery path. Present only when
  # the debug SSH path is enabled; otherwise the rule is omitted entirely.
  dynamic "ingress_security_rules" {
    for_each = var.enable_debug_ssh ? [1] : []

    content {
      protocol = "6" # TCP
      source   = var.debug_ssh_source_cidr

      tcp_options {
        min = 22
        max = 22
      }
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}
