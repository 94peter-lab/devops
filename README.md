# devops-infra

This repository contains the infrastructure configuration for GitHub Self-hosted Runners optimized for **Dagger CI**, designed to be deployed on **Coolify**.

## Project Structure

- `runners/base/`: Dockerfile, entrypoint script, `docker-compose.yaml`, and usage docs for the custom runner image — see [`runners/base/README.md`](runners/base/README.md).
- `.github/workflows/build-runner-image.yml`: Manually-triggered workflow to build and publish the runner image to GHCR.
- `examples/`: Contains an example GitHub Action workflow that utilizes the custom runner.

## Deployment on Coolify

1. Create a new **Docker Compose** project in Coolify.
2. Use the content from [`runners/base/docker-compose.yaml`](runners/base/docker-compose.yaml).
3. Set the environment variables described in [`runners/base/README.md`](runners/base/README.md#environment-variables).
4. Click **Deploy**.

For runner configuration details (environment variables, GitHub token resolution via Infisical, manual image builds, CI usage) see [`runners/base/README.md`](runners/base/README.md).
