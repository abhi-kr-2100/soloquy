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
  project_id  = vercel_project.soloquy_web_frontend.id
  production  = true
  ref         = "release"
}

resource "vercel_project_domain" "soloquy_web_frontend" {
  project_id = vercel_project.soloquy_web_frontend.id
  domain     = "soloquy.vercel.app"
}
