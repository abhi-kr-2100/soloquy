resource "oci_bastion_bastion" "this" {
  compartment_id   = oci_identity_compartment.soloquy_backend.id
  target_subnet_id = oci_core_subnet.this.id

  bastion_type = "STANDARD"
  name         = "soloquy-backend-bastion"

  client_cidr_block_allow_list = var.bastion_client_cidr_allow_list

  max_session_ttl_in_seconds = var.bastion_max_session_ttl_in_seconds
}

# Sessions are created on-demand using OCI CLI or Console
# Example CLI command:
# oci bastion session create-managed-ssh \
#   --bastion-id $(terraform output -raw bastion_id) \
#   --target-resource-id $(terraform output -raw instance_id) \
#   --target-port 22 \
#   --target-private-ip $(terraform output -raw instance_private_ip) \
#   --target-os-username <username> \
#   --ssh-public-key-file ~/.ssh/soloquy.pub \
#   --session-ttl 900

output "bastion_private_endpoint_ip" {
  description = "Private endpoint IP address of the OCI Bastion service — used in security list rules"
  value       = oci_bastion_bastion.this.private_endpoint_ip_address
}
