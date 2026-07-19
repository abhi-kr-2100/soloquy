terraform {
  required_version = "~> 1.15"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.23"
    }
  }

  cloud {
    organization = "soloquy"

    workspaces {
      project = "soloquy"
      name    = "soloquy-backend"
    }
  }
}
