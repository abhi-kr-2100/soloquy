# Build

## Prerequisites

If direnv is allowed, cd-ing into the project directory will automatically enter the devshell. To do so manually, run:

```bash
nix develop
```

## Frontend

```bash
pnpm --prefix soloquy-web-frontend install
```

```bash
pnpm --prefix soloquy-web-frontend dev      # dev server (localhost:3000)
```

```bash
pnpm --prefix soloquy-web-frontend build    # production build
```

```bash
pnpm --prefix soloquy-web-frontend start    # serve build
```

```bash
pnpm --prefix soloquy-web-frontend lint
```

## Backend

```bash
cd soloquybackend && ./gradlew test
```

```bash
cd soloquybackend && ./gradlew build
```

```bash
cd soloquybackend && ./gradlew nativeCompile   # GraalVM native executable
```

## Backend Docker image

```bash
nix build .#backend
docker load < result
docker run -p 8080:8080 soloquybackend:latest
```

## Deployment

Manages the Vercel frontend deployment (`soloquy.vercel.app` from the `release` branch via Terraform Cloud).

```bash
cd terraform
terraform init
terraform plan
terraform apply
```
