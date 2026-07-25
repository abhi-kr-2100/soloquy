variable "tenancy_ocid" {
  type        = string
  description = "OCID of the OCI tenancy. Supplied as an HCP Terraform Cloud workspace variable (sensitive)."
  sensitive   = true
}

variable "region" {
  type        = string
  description = "OCI region identifier, e.g. us-ashburn-1. Used by the Terraform OCI provider and the OL9 image lookup."
}

variable "user_ocid" {
  type        = string
  description = "OCID of the deployer API user. Supplied as an HCP workspace variable (sensitive)."
  sensitive   = true
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
  description = "Tag of the soloquybackend image to deploy. Always supplied by the GitHub Action at run time as the Nix store hash of the backend build."
}

variable "bastion_max_session_ttl_in_seconds" {
  type        = number
  description = "Maximum session TTL for Bastion in seconds. Default is 900 seconds (15 minutes)."
  default     = 1800
}

variable "bastion_client_cidr_allow_list" {
  type        = list(string)
  description = "CIDR blocks allowed to access the Bastion service. Default is 0.0.0.0/0 (any IP)."
  default     = ["0.0.0.0/0"]
}
