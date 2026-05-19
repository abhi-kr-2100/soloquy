variable "deploy_frontend" {
  type        = bool
  default     = true
  description = "Set to true to deploy the frontend Vercel resources."
}

variable "deploy_backend" {
  type        = bool
  default     = true
  description = "Set to true to deploy the backend GCP resources."
}

variable "vercel_team_id" {
  type        = string
  default     = "team_a55XpXai9FiU0iUz6k84YrAX"
  description = "The ID of the Vercel team for deployment."
}

variable "vercel_team_slug" {
  type        = string
  default     = "soloquy"
  description = "The slug of the Vercel team."
}

variable "frontend_domain" {
  type        = string
  default     = "soloquy.vercel.app"
  description = "The domain name for the frontend deployment on Vercel."
}

variable "gcp_project_id" {
  type        = string
  default     = "soloquy"
  description = "The GCP Project ID."
}

variable "gcp_region" {
  type        = string
  default     = "us-central1"
  description = "The GCP region for resources."
}

variable "gcp_registry_repo_id" {
  type        = string
  default     = "soloquy-registry"
  description = "The ID of the Google Artifact Registry repository."
}

variable "gcp_backend_image_name" {
  type        = string
  default     = "soloquybackend"
  description = "The name of the backend Docker image."
}

variable "gcp_backend_image_tag" {
  type        = string
  default     = "latest"
  description = "The tag of the backend Docker image."
}

variable "gcp_cloud_run_service_name" {
  type        = string
  default     = "soloquy-backend"
  description = "The name of the Google Cloud Run service."
}

variable "backend_image" {
  type        = string
  default     = ""
  description = "Optional override for the full backend Docker image URL."
}

variable "backend_port" {
  type        = number
  default     = 8080
  description = "The port the backend container listens on."
}
