# ──────────────────────────────────────────────
#  Input variables — populated from HCP Terraform workspace variables
# ──────────────────────────────────────────────

variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy."
  type        = string
  sensitive   = true
}

variable "user_ocid" {
  description = "OCID of the OCI user that owns the API key."
  type        = string
  sensitive   = true
}

variable "fingerprint" {
  description = "API-key fingerprint for the OCI user."
  type        = string
  sensitive   = true
}

variable "private_key" {
  description = "PEM private key content for OCI API auth."
  type        = string
  sensitive   = true
}

variable "private_key_pass_phrase" {
  description = "Pass phrase for the private key."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "OCI region identifier (e.g. ap-mumbai-1)."
  type        = string
  default     = "ap-hyderabad-1"
}

# ──────────────────────────────────────────────
#  Image / instance settings
# ──────────────────────────────────────────────

variable "instance_shape" {
  description = "Compute shape for the A1 VM."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "container_image_tag" {
  description = "Tag of the container image to pull from OCIR."
  type        = string
}
