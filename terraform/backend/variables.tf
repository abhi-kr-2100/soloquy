variable "tenancy_ocid" {
  type        = string
  description = "OCID of the OCI tenancy. Supplied as an HCP Terraform Cloud workspace variable (sensitive)."
  sensitive = true
}

variable "region" {
  type        = string
  description = "OCI region identifier, e.g. us-ashburn-1. Used by the Terraform OCI provider and the OL9 image lookup."
}

variable "user_ocid" {
  type        = string
  description = "OCID of the deployer API user. Supplied as an HCP workspace variable (sensitive)."
  sensitive = true
}

variable "fingerprint" {
  type        = string
  description = "Fingerprint of the deployer API key. Supplied as an HCP workspace variable (sensitive)."
  sensitive   = true
}

variable "private_key" {
  type        = string
  description = "PEM private key of the deployer API user. Supplied as an HCP workspace variable (sensitive)."
  sensitive   = true
}

variable "private_key_pass_phrase" {
  type        = string
  description = "Passphrase for the deployer API key. Supplied as an HCP workspace variable (sensitive)."
  sensitive   = true
}

variable "image_tag" {
  type        = string
  description = "Tag of the soloquybackend image to deploy. Always supplied by the GitHub Action at run time as the GitHub commit SHA."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key injected into the instance user_data for the Phase 5 recovery path. Leave null to disable SSH access entirely."
  default     = null
}

variable "debug_ssh_source_cidr" {
  type        = string
  description = "Source CIDR allowed ingress to TCP 22 for the Phase 5 SSH recovery path. Leave null to disable SSH ingress entirely."
  default     = null
}

variable "enable_debug_ssh" {
  type        = bool
  description = "Whether the SSH recovery path is active. When true, both ssh_public_key and debug_ssh_source_cidr must be set."
  default     = false
}

check "debug_ssh_requires_both" {
  assert {
    condition     = !var.enable_debug_ssh || (var.ssh_public_key != null && var.debug_ssh_source_cidr != null)
    error_message = "When enable_debug_ssh is true, both ssh_public_key and debug_ssh_source_cidr must be set."
  }
}
