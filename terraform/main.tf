terraform {
  required_providers {
    vercel = {
      source = "vercel/vercel"
      version = "~> 5.2"
    }
  }
}

resource "vercel_project" "soloquy_web_frontend" {
  name      = "soloquy-web-frontend"
  framework = "nextjs"
  team_id   = "team_a55XpXai9FiU0iUz6k84YrAX"
}

data "vercel_project_directory" "soloquy_web_frontend" {
  path = "../soloquy-web-frontend"
}

resource "vercel_deployment" "soloquy_web_frontend" {
  project_id  = vercel_project.soloquy_web_frontend.id
  files       = data.vercel_project_directory.soloquy_web_frontend.files
  path_prefix = "../soloquy-web-frontend"
  production  = true
}

resource "vercel_project_domain" "soloquy_web_frontend" {
  project_id = vercel_project.soloquy_web_frontend.id
  domain     = "soloquy.vercel.app"
}
