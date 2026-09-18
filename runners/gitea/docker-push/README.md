# Gitea Docker-Push Runner

Custom **Gitea Runner (`act_runner`)** docker image pre-installed with **Docker Buildx CLI plugin**, **Infisical CLI**, and Docker tooling for building & pushing multi-platform Docker images on Gitea.

## Features

- **Gitea Runner (`act_runner`)**: Native Gitea actions runner daemon.
- **Docker Buildx**: Pre-installed CLI plugin for `docker buildx build` multi-platform image builds.
- **Infisical Integration**: Dynamic retrieval of credentials from Infisical at startup.
- **Coolify Ready**: Deployable via Docker Compose on Coolify.

## Environment Variables

| Variable | Description |
| --- | --- |
| `GITEA_INSTANCE_URL` | Full URL of your Gitea instance (e.g. `https://gitea.example.com`) |
| `GITEA_RUNNER_REGISTRATION_TOKEN` | Registration token from Gitea |
| `RUNNER_NAME` | Name of the runner displayed in Gitea (Default: `gitea-docker-push-runner`) |
| `RUNNER_LABELS` | Comma-separated labels (Default: `docker-push:host,ubuntu-latest:docker://gitea/runner-images:ubuntu-latest,self-hosted:host`) |
| `INFISICAL_CLIENT_ID` | (Optional) Client ID for Infisical Universal Auth |
| `INFISICAL_CLIENT_SECRET` | (Optional) Client Secret for Infisical Universal Auth |
| `INFISICAL_PROJECT_ID` | (Optional) Project ID in Infisical |
| `INFISICAL_ENV` | (Optional) Infisical environment (Default: `prod`) |
