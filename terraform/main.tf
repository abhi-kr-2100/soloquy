terraform {
  required_version = ">= 1.3.0"

  required_providers {
    vercel = {
      source  = "vercel/vercel"
      version = "~> 5.2"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.32"
    }
  }
}

provider "vercel" {}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

resource "google_artifact_registry_repository" "backend" {
  count         = var.deploy_backend ? 1 : 0
  location      = var.gcp_region
  repository_id = var.gcp_registry_repo_id
  description   = "Docker registry for Soloquy backend images built by Nix flake"
  format        = "DOCKER"

  cleanup_policies {
    id     = "delete-old-versions"
    action = "DELETE"
    condition {
      tag_state = "ANY"
    }
  }

  cleanup_policies {
    id     = "keep-latest-2"
    action = "KEEP"
    most_recent_versions {
      keep_count = 2
    }
  }
}

resource "google_cloud_run_v2_service" "backend" {
  count               = var.deploy_backend ? 1 : 0
  name                = var.gcp_cloud_run_service_name
  location            = var.gcp_region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = true

  template {
    containers {
      image = var.backend_image != "" ? var.backend_image : "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.backend[0].repository_id}/${var.gcp_backend_image_name}:${var.gcp_backend_image_tag}"
      ports {
        container_port = var.backend_port
      }
    }
  }
}

resource "google_service_account" "vercel_invoker" {
  count        = var.deploy_backend ? 1 : 0
  account_id   = "vercel-invoker"
  display_name = "Service Account for Vercel Frontend to invoke Cloud Run Backend"
}

resource "google_cloud_run_v2_service_iam_member" "vercel_invoker" {
  count    = var.deploy_backend ? 1 : 0
  project  = google_cloud_run_v2_service.backend[0].project
  location = google_cloud_run_v2_service.backend[0].location
  name     = google_cloud_run_v2_service.backend[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.vercel_invoker[0].email}"
}

resource "google_iam_workload_identity_pool" "vercel" {
  count                     = var.deploy_backend ? 1 : 0
  workload_identity_pool_id = "vercel-pool"
  display_name              = "Vercel OIDC Pool"
  description               = "Workload Identity Pool for Vercel integration"
}

resource "google_iam_workload_identity_pool_provider" "vercel" {
  count                              = var.deploy_backend ? 1 : 0
  workload_identity_pool_id          = google_iam_workload_identity_pool.vercel[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "vercel-provider"
  display_name                       = "Vercel OIDC Provider"

  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.project_id"  = "assertion.project_id"
    "attribute.team_id"     = "assertion.team_id"
    "attribute.environment" = "assertion.environment"
  }

  oidc {
    issuer_uri        = "https://oidc.vercel.com"
    allowed_audiences = ["https://vercel.com/${var.vercel_team_slug}"]
  }
}

resource "google_service_account_iam_member" "vercel_oidc" {
  count              = var.deploy_backend && var.deploy_frontend ? 1 : 0
  service_account_id = google_service_account.vercel_invoker[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.vercel[0].name}/attribute.project_id/${vercel_project.soloquy_web_frontend[0].id}"
}

resource "vercel_project" "soloquy_web_frontend" {
  count     = var.deploy_frontend ? 1 : 0
  name      = "soloquy-web-frontend"
  framework = "nextjs"
  team_id   = var.vercel_team_id
}

data "vercel_project_directory" "soloquy_web_frontend" {
  count = var.deploy_frontend ? 1 : 0
  path  = "../soloquy-web-frontend"
}

resource "vercel_deployment" "soloquy_web_frontend" {
  count       = var.deploy_frontend ? 1 : 0
  project_id  = vercel_project.soloquy_web_frontend[0].id
  files       = data.vercel_project_directory.soloquy_web_frontend[0].files
  path_prefix = "../soloquy-web-frontend"
  production  = true
}

resource "vercel_project_domain" "soloquy_web_frontend" {
  count      = var.deploy_frontend ? 1 : 0
  project_id = vercel_project.soloquy_web_frontend[0].id
  domain     = var.frontend_domain
}

resource "vercel_project_environment_variable" "backend_url" {
  count      = var.deploy_frontend && var.deploy_backend ? 1 : 0
  project_id = vercel_project.soloquy_web_frontend[0].id
  key        = "API_URL"
  value      = google_cloud_run_v2_service.backend[0].uri
  target     = ["production", "preview", "development"]
  sensitive  = false
}

resource "vercel_project_environment_variable" "gcp_workload_identity_provider" {
  count      = var.deploy_frontend && var.deploy_backend ? 1 : 0
  project_id = vercel_project.soloquy_web_frontend[0].id
  key        = "GCP_WORKLOAD_IDENTITY_PROVIDER"
  value      = google_iam_workload_identity_pool_provider.vercel[0].name
  target     = ["production", "preview", "development"]
  sensitive  = false
}

resource "vercel_project_environment_variable" "gcp_service_account_email" {
  count      = var.deploy_frontend && var.deploy_backend ? 1 : 0
  project_id = vercel_project.soloquy_web_frontend[0].id
  key        = "GCP_SERVICE_ACCOUNT_EMAIL"
  value      = google_service_account.vercel_invoker[0].email
  target     = ["production", "preview", "development"]
  sensitive  = false
}
