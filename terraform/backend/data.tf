# ──────────────────────────────────────────────
#  Resolved locals
# ──────────────────────────────────────────────

locals {
  compartment_id = oci_identity_compartment.backend.id

  # OCIR hostname is derived from the region key
  ocir_host = "${var.region}.ocir.io"
}

# ──────────────────────────────────────────────
#  Tenancy namespace — required for OCIR paths
# ──────────────────────────────────────────────

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.tenancy_ocid
}

# ──────────────────────────────────────────────
#  Availability domain — pick the first (AF tier has one)
# ──────────────────────────────────────────────

data "oci_identity_availability_domains" "this" {
  compartment_id = var.tenancy_ocid
}

# ──────────────────────────────────────────────
#  Latest Oracle Linux 9 aarch64 platform image
# ──────────────────────────────────────────────

data "oci_core_images" "ol9_aarch64" {
  compartment_id           = local.compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}
