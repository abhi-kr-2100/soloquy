# ──────────────────────────────────────────────
#  Outputs — the frontend needs the backend IP to connect
# ──────────────────────────────────────────────

output "instance_public_ip" {
  description = "Public IP of the backend A1 instance."
  value       = oci_core_instance.backend.public_ip
}
