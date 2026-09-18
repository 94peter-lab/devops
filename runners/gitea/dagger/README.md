# Gitea Dagger Runner

Custom **Gitea Runner (`act_runner`)** docker image pre-installed with **Dagger CLI**, **Infisical CLI**, and Docker tooling for CI/CD automation on Gitea instances.

## Features

- **Gitea Runner (`act_runner`)**: Native Gitea actions runner daemon.
- **Dagger CLI**: Pre-installed for running containerized Dagger pipelines.
- **Infisical Integration**: Dynamic retrieval of `GITEA_INSTANCE_URL` and `GITEA_RUNNER_REGISTRATION_TOKEN` from Infisical at startup.
- **Coolify Ready**: Easily deployable via Docker Compose on Coolify or Docker hosts.

## Environment Variables

| Variable | Description |
| --- | --- |
| `GITEA_INSTANCE_URL` | Full URL of your Gitea instance (e.g. `https://gitea.example.com`) |
| `GITEA_RUNNER_REGISTRATION_TOKEN` | Registration token from Gitea (Org or Repository settings) |
| `RUNNER_NAME` | Name of the runner displayed in Gitea (Default: `gitea-dagger-runner`) |
| `RUNNER_LABELS` | Comma-separated labels (Default: `ubuntu-latest:docker://gitea/runner-images:ubuntu-latest,self-hosted:host`) |
| `INFISICAL_CLIENT_ID` | (Optional) Client ID for Infisical Universal Auth |
| `INFISICAL_CLIENT_SECRET` | (Optional) Client Secret for Infisical Universal Auth |
| `INFISICAL_PROJECT_ID` | (Optional) Project ID in Infisical |
| `INFISICAL_ENV` | (Optional) Infisical environment (Default: `prod`) |

## Coolify Deployment

1. Create a **Docker Compose** application in Coolify.
2. Paste the contents of `docker-compose.yaml`.
3. Configure the required environment variables (`GITEA_INSTANCE_URL` and `GITEA_RUNNER_REGISTRATION_TOKEN` or Infisical variables).
4. Deploy!
