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
| `GITHUB_TOKEN` | GitHub Personal Access Token with runner registration permissions. Optional if a GitHub App or Infisical is set up instead — see [Credential Resolution](#credential-resolution). |
| `GITHUB_APP_ID` | GitHub App ID, for minting an installation access token instead of using a PAT. Set together with `GITHUB_APP_PRIVATE_KEY`(`_BASE64`) and `GITHUB_APP_INSTALLATION_ID` — see [Credential Resolution](#credential-resolution). |
| `GITHUB_APP_PRIVATE_KEY` / `GITHUB_APP_PRIVATE_KEY_BASE64` | The GitHub App's private key: either the literal PEM (`GITHUB_APP_PRIVATE_KEY`) or a base64-encoded PEM (`GITHUB_APP_PRIVATE_KEY_BASE64`, for env vars that don't handle multi-line values well). |
| `GITHUB_APP_INSTALLATION_ID` | The GitHub App's installation ID on the target org/repo. |
| `RUNNER_LABELS` | Additional labels for the runner (default: `self-hosted`). |
| `RUNNER_NAME` | Name to register the runner under (default: container hostname). |
| `DAGGER_VERSION`| The version of Dagger to label the runner with (default: `0.12.0`). Purely a display label at runtime — it should match the version actually baked into `RUNNER_IMAGE`, but nothing enforces that; keep them in sync yourself. |

### Credential Resolution

Every credential the entrypoint needs (`GITHUB_TOKEN`, `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`, `GITHUB_APP_INSTALLATION_ID`) is resolved the same way: **the environment variable of that exact name if set, otherwise an Infisical secret of that exact same name** (if Infisical is configured) — there's no way to rename what secret in Infisical backs which variable. `GITHUB_APP_PRIVATE_KEY` is the one exception in storage format: Infisical stores it as the raw multi-line PEM, while an env var must supply it base64-encoded as `GITHUB_APP_PRIVATE_KEY_BASE64` instead (multi-line env vars are awkward in most UIs, including Coolify's).

This lets you avoid storing long-lived credentials in Coolify/`.env` directly — the container only holds an Infisical machine identity, and the actual credential is pulled at container start.

| Variable | Description |
|----------|-------------|
| `INFISICAL_CLIENT_ID` | Universal Auth client ID for an Infisical machine identity. Required to use Infisical. |
| `INFISICAL_CLIENT_SECRET` | Universal Auth client secret for the machine identity. Required to use Infisical. |
| `INFISICAL_PROJECT_ID` | The Infisical project (workspace) ID containing the secrets. Required to use Infisical. |
| `INFISICAL_ENV` | Infisical environment slug to read from (default: `prod`). |
| `INFISICAL_SECRET_PATH` | Secret path within the project (default: `/`). |
| `INFISICAL_API_URL` | Only needed for a self-hosted Infisical instance; the CLI reads this automatically. |

Resolution order at container start:
1. Resolve `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`, and `GITHUB_APP_INSTALLATION_ID` (env, else Infisical). If all three resolve, mint a GitHub App installation access token and use it — **this takes priority even if `GITHUB_TOKEN` also resolves to something.**
2. Otherwise, resolve `GITHUB_TOKEN` (env, else Infisical) and use it as-is.
3. If neither resolved anything, the entrypoint logs an error and exits (`exit 1`).

Installation access tokens expire after 1 hour. Since this runner is long-lived, `cleanup()` mints a fresh one (rather than reusing the one from startup) before deregistering the runner on shutdown.

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
   - `GITHUB_TOKEN` **or** `GITHUB_APP_ID`/`GITHUB_APP_PRIVATE_KEY(_BASE64)`/`GITHUB_APP_INSTALLATION_ID` **or** `INFISICAL_CLIENT_ID`/`INFISICAL_CLIENT_SECRET`/`INFISICAL_PROJECT_ID` — see [Credential Resolution](#credential-resolution).
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
