resource "vercel_project" "soloquy_web_frontend" {
  name      = "soloquy-web-frontend"
  framework = "nextjs"
  team_id   = "team_a55XpXai9FiU0iUz6k84YrAX"

  git_repository = {
    type = "github"
    repo = "abhi-kr-2100/soloquy"
  }

  root_directory = "soloquy-web-frontend"
}

resource "vercel_deployment" "soloquy_web_frontend" {
  project_id = vercel_project.soloquy_web_frontend.id
  production = true
  ref        = "release"

  environment = {
    API_URL = var.api_url
  }
}

resource "vercel_project_domain" "soloquy_web_frontend" {
  project_id = vercel_project.soloquy_web_frontend.id
  domain     = "soloquy.vercel.app"
}

resource "vercel_project_environment_variable" "api_url" {
  project_id = vercel_project.soloquy_web_frontend.id
  key        = "API_URL"
  value      = var.api_url
  target     = ["production"]
  sensitive  = false
}

variable "api_url" {
  type      = string
  sensitive = false
}
