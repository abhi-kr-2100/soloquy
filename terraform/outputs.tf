output "frontend_domain_url" {
  description = "The primary custom domain URL of the Vercel frontend"
  value       = var.deploy_frontend ? "https://${var.frontend_domain}" : null
}

output "frontend_deployment_url" {
  description = "The Vercel-generated unique deployment URL of the frontend"
  value       = var.deploy_frontend ? "https://${vercel_deployment.soloquy_web_frontend[0].url}" : null
}

output "backend_url" {
  description = "The URL (URI) of the backend service on Google Cloud Run"
  value       = var.deploy_backend ? google_cloud_run_v2_service.backend[0].uri : null
}

output "artifact_registry_repository_url" {
  description = "The Google Artifact Registry repository URL where you must tag and push the backend Docker image"
  value       = var.deploy_backend ? "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.backend[0].repository_id}" : null
}
