terraform {
  required_version = "~> 1.15"

  required_providers {
    vercel = {
      source  = "vercel/vercel"
      version = "~> 5.2"
    }
  }

  cloud {
    organization = "soloquy"

    workspaces {
      project = "soloquy"
      name = "soloquy-frontend"
    }
  }
}
