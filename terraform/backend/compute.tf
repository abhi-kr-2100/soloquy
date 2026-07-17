# ──────────────────────────────────────────────
#  Cloud-init user_data — installs podman, pulls
#  from OCIR via Instance Principal, runs the
#  container as a systemd Quadlet unit.
# ──────────────────────────────────────────────

locals {
  ocir_image = "${local.ocir_host}/${data.oci_objectstorage_namespace.this.namespace}/soloquybackend:${var.container_image_tag}"

  cloud_init = templatefile("${path.module}/templates/cloud-init.sh.tftpl", {
    ocir_host      = local.ocir_host
    ocir_namespace = data.oci_objectstorage_namespace.this.namespace
    ocir_image     = local.ocir_image
  })
}

# ──────────────────────────────────────────────
#  A1 Ampere compute instance
# ──────────────────────────────────────────────

resource "oci_core_instance" "backend" {
  compartment_id      = local.compartment_id
  availability_domain = data.oci_identity_availability_domains.this.availability_domains[0].name
  display_name        = "soloquy-backend"
  shape               = var.instance_shape

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ol9_aarch64.images[0].id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id    = oci_core_subnet.backend.id
    display_name = "soloquy-backend-vnic"
  }

  metadata = {
    user_data = base64encode(local.cloud_init)
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  # Instance Principal requires the dynamic group to exist, but since
  # the dynamic group references this instance's OCID, we accept that
  # cloud-init may run before the policy propagates. The Quadlet
  # Restart=always handles the retry.
}
