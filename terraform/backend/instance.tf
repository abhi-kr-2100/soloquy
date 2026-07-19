module "soloquy_backend_instance" {
  source  = "oracle-terraform-modules/compute-instance/oci"
  version = "2.4.1"

  compartment_ocid = oci_identity_compartment.soloquy_backend.id
  subnet_ocids     = [oci_core_subnet.this.id]
  source_ocid      = local.ol9_x86_64_image_ocid
  ssh_public_keys  = var.enable_debug_ssh ? var.ssh_public_key : ""

  ad_number             = 1
  shape                 = "VM.Standard.E2.1.Micro"
  instance_display_name = "soloquy-backend-instance"

  assign_public_ip       = false
  public_ip              = "RESERVED"
  public_ip_display_name = "soloquy-backend-public-ip"
}

output "instance_id" {
  description = "OCID of the soloquy-backend instance."
  value       = module.soloquy_backend_instance.instance_id[0]
}

output "instance_public_ip" {
  description = "Reserved public IP address attached to the soloquy-backend instance."
  value       = module.soloquy_backend_instance.public_ip[0]
}

output "instance_public_ip_ocid" {
  description = "OCID of the reserved public IP resource for the soloquy-backend instance."
  value       = module.soloquy_backend_instance.public_ip_all_attributes[0].id
}
