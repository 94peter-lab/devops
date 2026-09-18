# devops-infra

This repository contains the infrastructure configuration for GitHub & Gitea Self-hosted Runners optimized for **Dagger CI** and Docker build workflows, designed to be deployed on **Coolify**.

## Project Structure

- `runners/github/dagger/`: GitHub Actions runner image pre-installed with Dagger CLI & Infisical — see [`runners/github/dagger/README.md`](runners/github/dagger/README.md).
- `runners/github/docker-push/`: GitHub Actions runner image with Docker Buildx pre-installed.
- `runners/gitea/dagger/`: Gitea runner (`act_runner`) image pre-installed with Dagger CLI & Infisical — see [`runners/gitea/dagger/README.md`](runners/gitea/dagger/README.md).
- `runners/gitea/docker-push/`: Gitea runner (`act_runner`) image with Docker Buildx pre-installed — see [`runners/gitea/docker-push/README.md`](runners/gitea/docker-push/README.md).
- `.github/workflows/`: Workflows to build and publish runner images to GHCR.
- `examples/`: Example workflow files utilizing custom runners.

## Deployment on Coolify

1. Create a new **Docker Compose** project in Coolify.
2. Select the runner compose file for your platform (`runners/github/dagger/docker-compose.yaml` or `runners/gitea/dagger/docker-compose.yaml`).
3. Set the required environment variables (e.g. `GITHUB_TOKEN` / `GITEA_INSTANCE_URL` & `GITEA_RUNNER_REGISTRATION_TOKEN`, or Infisical credentials).
4. Click **Deploy**.
