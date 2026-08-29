#!/bin/bash
set -e

# Validate required environment variables
if [ -z "$REPO_URL" ]; then
  echo "Error: REPO_URL is not set."
  exit 1
fi

# REGISTRY_URL is optional: set it (along with REGISTRY_USERNAME /
# REGISTRY_PASSWORD) only if jobs also need to push to a private registry.
# GHCR login (via GITHUB_TOKEN) always happens below regardless.

# Automatically strip .git suffix and trailing slashes
REPO_URL=$(echo "${REPO_URL}" | sed 's/\.git$//' | sed 's/\/$//')

# Extract Owner and Repo from URL (e.g., https://github.com/owner/repo)
OWNER_REPO=$(echo "${REPO_URL}" | sed 's/.*github.com\///')
OWNER=$(echo "${OWNER_REPO}" | cut -d'/' -f1)

echo "Detected Repo: ${OWNER_REPO}"

# Resolve GITHUB_TOKEN and registry credentials, falling back to Infisical
# (Universal Auth) for any that are not set directly.
GHCR_USERNAME=${GHCR_USERNAME:-$OWNER}
INFISICAL_ENV=${INFISICAL_ENV:-prod}
INFISICAL_SECRET_PATH=${INFISICAL_SECRET_PATH:-/}

NEED_INFISICAL=false
[ -z "$GITHUB_TOKEN" ] && NEED_INFISICAL=true
if [ -n "$REGISTRY_URL" ]; then
  [ -z "$REGISTRY_USERNAME" ] && NEED_INFISICAL=true
  [ -z "$REGISTRY_PASSWORD" ] && NEED_INFISICAL=true
fi

INFISICAL_TOKEN=""
if [ "$NEED_INFISICAL" = true ]; then
  if [ -z "$INFISICAL_CLIENT_ID" ] || [ -z "$INFISICAL_CLIENT_SECRET" ] || [ -z "$INFISICAL_PROJECT_ID" ]; then
    echo "Error: GITHUB_TOKEN (and REGISTRY_USERNAME / REGISTRY_PASSWORD, if REGISTRY_URL is set) are not all set directly, and INFISICAL_CLIENT_ID / INFISICAL_CLIENT_SECRET / INFISICAL_PROJECT_ID are not all set to fetch the missing ones from Infisical."
    exit 1
  fi

  echo "Fetching missing secrets from Infisical..."
  INFISICAL_TOKEN=$(infisical login \
    --method=universal-auth \
    --client-id="${INFISICAL_CLIENT_ID}" \
    --client-secret="${INFISICAL_CLIENT_SECRET}" \
    --silent --plain) || true

  if [ -z "$INFISICAL_TOKEN" ]; then
    echo "Error: Failed to authenticate with Infisical (check INFISICAL_CLIENT_ID/INFISICAL_CLIENT_SECRET)."
    exit 1
  fi
fi

# fetch_secret <secret_name>
fetch_secret() {
  infisical secrets get "$1" \
    --projectId="${INFISICAL_PROJECT_ID}" \
    --env="${INFISICAL_ENV}" \
    --path="${INFISICAL_SECRET_PATH}" \
    --token="${INFISICAL_TOKEN}" \
    --plain
}

if [ -z "$GITHUB_TOKEN" ]; then
  GITHUB_TOKEN=$(fetch_secret "GITHUB_TOKEN") || true
  if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: Failed to fetch secret 'GITHUB_TOKEN' from Infisical (project ${INFISICAL_PROJECT_ID}, env ${INFISICAL_ENV}, path ${INFISICAL_SECRET_PATH})."
    exit 1
  fi
fi

if [ -n "$REGISTRY_URL" ]; then
  if [ -z "$REGISTRY_USERNAME" ]; then
    REGISTRY_USERNAME=$(fetch_secret "REGISTRY_USERNAME") || true
    if [ -z "$REGISTRY_USERNAME" ]; then
      echo "Error: Failed to fetch secret 'REGISTRY_USERNAME' from Infisical (project ${INFISICAL_PROJECT_ID}, env ${INFISICAL_ENV}, path ${INFISICAL_SECRET_PATH})."
      exit 1
    fi
  fi

  if [ -z "$REGISTRY_PASSWORD" ]; then
    REGISTRY_PASSWORD=$(fetch_secret "REGISTRY_PASSWORD") || true
    if [ -z "$REGISTRY_PASSWORD" ]; then
      echo "Error: Failed to fetch secret 'REGISTRY_PASSWORD' from Infisical (project ${INFISICAL_PROJECT_ID}, env ${INFISICAL_ENV}, path ${INFISICAL_SECRET_PATH})."
      exit 1
    fi
  fi
fi

# Fix Docker socket permissions if it exists
if [ -S /var/run/docker.sock ]; then
  echo "Fixing Docker socket permissions..."
  sudo chmod 666 /var/run/docker.sock
fi

# Log in to the private registry, if configured
if [ -n "$REGISTRY_URL" ]; then
  echo "Logging in to ${REGISTRY_URL}..."
  echo "${REGISTRY_PASSWORD}" | docker login "${REGISTRY_URL}" -u "${REGISTRY_USERNAME}" --password-stdin
fi

# Log in to GHCR (reuses GITHUB_TOKEN as the password)
echo "Logging in to ghcr.io as ${GHCR_USERNAME}..."
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GHCR_USERNAME}" --password-stdin

# Set up Docker Buildx so jobs can run `docker buildx build`, including
# multi-platform builds (e.g. --platform linux/amd64,linux/arm64).
BUILDX_BUILDER_NAME=${BUILDX_BUILDER_NAME:-docker-push-builder}
ENABLE_QEMU=${ENABLE_QEMU:-true}

if [ "$ENABLE_QEMU" = "true" ]; then
  echo "Installing QEMU emulators for multi-platform builds..."
  docker run --privileged --rm tonistiigi/binfmt --install all
fi

echo "Setting up buildx builder '${BUILDX_BUILDER_NAME}'..."
if ! docker buildx inspect "${BUILDX_BUILDER_NAME}" >/dev/null 2>&1; then
  docker buildx create --name "${BUILDX_BUILDER_NAME}" --driver docker-container --bootstrap
fi
docker buildx use "${BUILDX_BUILDER_NAME}"

# 1. Get a Registration Token via API
echo "Fetching registration token from GitHub..."
REG_TOKEN=$(curl -s -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${OWNER_REPO}/actions/runners/registration-token" | jq -r '.token')

if [ "$REG_TOKEN" == "null" ] || [ -z "$REG_TOKEN" ]; then
  echo "Error: Failed to get registration token. Check your GITHUB_TOKEN permissions and REPO_URL."
  exit 1
fi

RUNNER_LABELS=${RUNNER_LABELS:-"self-hosted,docker-push"}
RUNNER_NAME=${RUNNER_NAME:-$(hostname)}

echo "Configuring runner ${RUNNER_NAME} for ${REPO_URL} with labels: ${RUNNER_LABELS}"

# Navigate to runner directory
cd /home/runner

# 2. Register the runner using the retrieved Registration Token
./config.sh --url "${REPO_URL}" \
            --token "${REG_TOKEN}" \
            --name "${RUNNER_NAME}" \
            --labels "${RUNNER_LABELS}" \
            --unattended \
            --replace

# Define cleanup function
cleanup() {
    set +e
    echo "Removing runner ${RUNNER_NAME}..."
    # Get a fresh removal token
    REMOVE_TOKEN=$(curl -s -X POST \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/${OWNER_REPO}/actions/runners/remove-token" | jq -r '.token')

    if [ "$REMOVE_TOKEN" != "null" ] && [ -n "$REMOVE_TOKEN" ]; then
        ./config.sh remove --token "${REMOVE_TOKEN}"
    else
        echo "Failed to get removal token, cannot remove runner from GitHub."
    fi

    docker buildx rm "${BUILDX_BUILDER_NAME}" >/dev/null 2>&1 || true
    if [ -n "$REGISTRY_URL" ]; then
      docker logout "${REGISTRY_URL}" >/dev/null 2>&1 || true
    fi
    docker logout ghcr.io >/dev/null 2>&1 || true
}

# Trap signals for graceful shutdown
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup' EXIT

# Start the runner
./run.sh &
wait $!
