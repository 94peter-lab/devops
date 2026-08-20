# devops-infra

This repository contains the infrastructure configuration for GitHub Self-hosted Runners optimized for **Dagger CI**, designed to be deployed on **Coolify**.

## Project Structure

- `docker-compose.yaml`: The main configuration for deploying via Coolify.
- `runners/base/`: Contains the Dockerfile and entrypoint script for the custom runner image.
- `examples/`: Contains an example GitHub Action workflow that utilizes the custom runner.

## Key Features

- **Dagger CLI Integrated**: Dagger is pre-installed in the runner image.
- **Dynamic Labeling**: The runner automatically registers itself with a label indicating the Dagger version (e.g., `dagger:0.12.0`).
- **Graceful Cleanup**: Uses `trap` to ensure the runner is removed from GitHub when the container stops.
- **Non-root Execution**: The runner process executes as the `runner` user for security.
- **Docker-in-Docker Support**: Mounts the Docker socket to allow Dagger and other Docker operations.
- **Caching**: Persistent volume for Dagger cache (`/home/runner/.cache/dagger`).

## Environment Variables

The following environment variables configure the runner:

| Variable | Description |
|----------|-------------|
| `REPO_URL` | The URL of the repository or organization to register the runner with. |
| `GITHUB_TOKEN` | GitHub Personal Access Token with runner registration permissions. Optional if the `INFISICAL_*` variables below are set instead — see [GitHub Token Resolution](#github-token-resolution). |
| `RUNNER_LABELS` | Additional labels for the runner (default: `self-hosted`). |
| `RUNNER_NAME` | Name to register the runner under (default: container hostname). |
| `DAGGER_VERSION`| The version of Dagger to label the runner with (default: `0.12.0`). |

### Fetching `GITHUB_TOKEN` from Infisical

If `GITHUB_TOKEN` is not set, the entrypoint tries to fetch it from [Infisical](https://infisical.com) using Universal Auth. This lets you avoid storing a long-lived PAT in Coolify/`.env` — the container only holds a machine identity credential, and the actual token is pulled at container start.

| Variable | Description |
|----------|-------------|
| `INFISICAL_CLIENT_ID` | Universal Auth client ID for an Infisical machine identity. Required. |
| `INFISICAL_CLIENT_SECRET` | Universal Auth client secret for the machine identity. Required. |
| `INFISICAL_PROJECT_ID` | The Infisical project (workspace) ID containing the secret. Required. |
| `INFISICAL_ENV` | Infisical environment slug to read from (default: `prod`). |
| `INFISICAL_SECRET_PATH` | Secret path within the project (default: `/`). |
| `INFISICAL_SECRET_NAME` | Name of the secret holding the GitHub token (default: `GITHUB_TOKEN`). |
| `INFISICAL_API_URL` | Only needed for a self-hosted Infisical instance; the CLI reads this automatically. |

Resolution order at container start:
1. `GITHUB_TOKEN` is set → used as-is.
2. `GITHUB_TOKEN` is unset, but `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET`, and `INFISICAL_PROJECT_ID` are all set → the entrypoint authenticates to Infisical and fetches `INFISICAL_SECRET_NAME` to use as the token.
3. Neither is available → the entrypoint logs an error and exits (`exit 1`).

## Deployment & Image Building

### 1. Coolify Deployment (Internal Build)
This project is designed to be built directly by Coolify.
- Coolify will pull this repository and use the `Dockerfile` to build the runner image locally.
- Set the `DAGGER_VERSION` environment variable in Coolify (e.g., `0.20.3`).
- Coolify will pass this to the Docker build process as a `build_arg`.

### 2. Manual Local Build (Optional)
```bash
docker build -t devops-runner:v0.20.3 \
  --build-arg DAGGER_VERSION=0.20.3 \
  ./runners/base
```

## Deployment on Coolify

1. Create a new **Docker Compose** project in Coolify.
2. Use the content from `docker-compose.yaml`.
3. Set the following Environment Variables in Coolify:
   - `REPO_URL`: Your repository URL.
   - `GITHUB_TOKEN`: Your GitHub PAT — **or** `INFISICAL_CLIENT_ID` / `INFISICAL_CLIENT_SECRET` / `INFISICAL_PROJECT_ID` to fetch it from Infisical instead (see [GitHub Token Resolution](#github-token-resolution)).
   - `DAGGER_VERSION`: The desired Dagger version (e.g., `0.20.3`).
4. Click **Deploy**.

## CI Usage

In your GitHub Action workflows, use:

```yaml
jobs:
  ci:
    runs-on: [self-hosted, "dagger:0.12.0"]
    steps:
      - run: dagger run go run ci/main.go
```
