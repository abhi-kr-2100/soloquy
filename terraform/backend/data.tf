provider "oci" {
  tenancy_ocid         = var.tenancy_ocid
  user_ocid            = var.user_ocid
  fingerprint          = var.fingerprint
  private_key          = var.private_key
  private_key_password = var.private_key_pass_phrase
  region               = var.region
}

data "oci_objectstorage_namespace" "this" {}

data "oci_identity_availability_domains" "this" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ol9" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  ol9_x86_64_image_ocid = data.oci_core_images.ol9.images[0].id

  # OCIR registry host, in the region-identifier form used by the deploy
  # workflow's push/login. Must match the credHelpers key and the VM pull
  # exactly per docs/oci-backend-deployment-steps.md §1.4.
  ocir_registry_host = "ocir.${var.region}.oci.oraclecloud.com"
}
