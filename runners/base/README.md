# Runner Image (base)

The Dockerfile and entrypoint script for the custom GitHub Actions self-hosted runner image, with Dagger CI pre-installed. Supports both repo-level and org-level runner registration.

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
| `RUNNER_IMAGE` | Full GHCR image reference to pull (e.g. `ghcr.io/94peter-lab/gh-runner:2.319.1-dagger-0.20.3`), published by the [`build-runner-image.yml`](#3-publish-to-ghcr-manual) workflow. Required — there is no default/`latest` tag. |
| `REPO_URL` | Repository URL to register a repo-level runner with (e.g. `https://github.com/owner/repo`). Set exactly one of `REPO_URL` or `ORG_URL`. |
| `ORG_URL` | Organization URL to register an org-level runner with (e.g. `https://github.com/my-org`). Set exactly one of `REPO_URL` or `ORG_URL`. Requires `GITHUB_TOKEN` with the `admin:org` scope (classic PAT) or the Organization "Self-hosted runners: Read and write" permission (fine-grained PAT / GitHub App), instead of the repo-level `repo` scope / Administration permission. |
| `GITHUB_TOKEN` | GitHub Personal Access Token with runner registration permissions. Optional if the `INFISICAL_*` variables below are set instead — see [GitHub Token Resolution](#github-token-resolution). |
| `RUNNER_LABELS` | Additional labels for the runner (default: `self-hosted`). |
| `RUNNER_NAME` | Name to register the runner under (default: container hostname). |
| `DAGGER_VERSION`| The version of Dagger to label the runner with (default: `0.12.0`). Purely a display label at runtime — it should match the version actually baked into `RUNNER_IMAGE`, but nothing enforces that; keep them in sync yourself. |

### GitHub Token Resolution

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

### 1. Coolify Deployment (Pulls a Pre-built Image)
`docker-compose.yaml` no longer builds from the `Dockerfile` — Coolify just pulls whatever image you set in `RUNNER_IMAGE`.
- Publish an image first via the [GHCR workflow](#3-publish-to-ghcr-manual) below.
- Set `RUNNER_IMAGE` in Coolify to that published tag (e.g. `ghcr.io/94peter-lab/gh-runner:2.319.1-dagger-0.20.3`).
- To roll out a new Dagger or runner version, publish a new image and update `RUNNER_IMAGE` — no rebuild happens on the Coolify side.

### 2. Manual Local Build (Optional)
```bash
docker build -t devops-runner:v0.20.3 \
  --build-arg DAGGER_VERSION=0.20.3 \
  --build-arg RUNNER_VERSION=latest \
  ./runners/base
```

### 3. Publish to GHCR (Manual)
The [`build-runner-image.yml`](../../.github/workflows/build-runner-image.yml) workflow builds this image and pushes it to GHCR. It only runs on manual `workflow_dispatch` — trigger it from the Actions tab and supply:
- `dagger_version`: Dagger CLI version to bake in.
- `runner_version`: `ghcr.io/actions/actions-runner` base image tag to build from.

The resulting image is published as `ghcr.io/<owner>/gh-runner:<runner_version>-dagger-<dagger_version>`.

## Deployment on Coolify

1. Create a new **Docker Compose** project in Coolify.
2. Use the content from [`docker-compose.yaml`](docker-compose.yaml).
3. Set the following Environment Variables in Coolify:
   - `RUNNER_IMAGE`: The GHCR image tag to pull (see [Publish to GHCR](#3-publish-to-ghcr-manual)).
   - `REPO_URL` (or `ORG_URL` for an org-level runner): the repository/organization URL.
   - `GITHUB_TOKEN`: Your GitHub PAT — **or** `INFISICAL_CLIENT_ID` / `INFISICAL_CLIENT_SECRET` / `INFISICAL_PROJECT_ID` to fetch it from Infisical instead (see [GitHub Token Resolution](#github-token-resolution)).
   - `DAGGER_VERSION`: The Dagger version baked into `RUNNER_IMAGE`, for the runner label (e.g., `0.20.3`).
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
