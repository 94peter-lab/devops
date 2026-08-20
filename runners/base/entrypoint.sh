#!/bin/bash
set -e

# Validate required environment variables
if [ -z "$REPO_URL" ]; then
  echo "Error: REPO_URL is not set."
  exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
  if [ -n "$INFISICAL_CLIENT_ID" ] && [ -n "$INFISICAL_CLIENT_SECRET" ] && [ -n "$INFISICAL_PROJECT_ID" ]; then
    echo "GITHUB_TOKEN not set, fetching it from Infisical..."

    INFISICAL_ENV=${INFISICAL_ENV:-prod}
    INFISICAL_SECRET_PATH=${INFISICAL_SECRET_PATH:-/}
    INFISICAL_SECRET_NAME=${INFISICAL_SECRET_NAME:-GITHUB_TOKEN}

    INFISICAL_TOKEN=$(infisical login \
      --method=universal-auth \
      --client-id="${INFISICAL_CLIENT_ID}" \
      --client-secret="${INFISICAL_CLIENT_SECRET}" \
      --silent --plain) || true

    if [ -z "$INFISICAL_TOKEN" ]; then
      echo "Error: Failed to authenticate with Infisical (check INFISICAL_CLIENT_ID/INFISICAL_CLIENT_SECRET)."
      exit 1
    fi

    GITHUB_TOKEN=$(infisical secrets get "${INFISICAL_SECRET_NAME}" \
      --projectId="${INFISICAL_PROJECT_ID}" \
      --env="${INFISICAL_ENV}" \
      --path="${INFISICAL_SECRET_PATH}" \
      --token="${INFISICAL_TOKEN}" \
      --plain) || true

    if [ -z "$GITHUB_TOKEN" ]; then
      echo "Error: Failed to fetch secret '${INFISICAL_SECRET_NAME}' from Infisical (project ${INFISICAL_PROJECT_ID}, env ${INFISICAL_ENV}, path ${INFISICAL_SECRET_PATH})."
      exit 1
    fi
  else
    echo "Error: GITHUB_TOKEN is not set, and INFISICAL_CLIENT_ID / INFISICAL_CLIENT_SECRET / INFISICAL_PROJECT_ID are not all set to fetch it from Infisical."
    exit 1
  fi
fi

# Automatically strip .git suffix and trailing slashes
REPO_URL=$(echo "${REPO_URL}" | sed 's/\.git$//' | sed 's/\/$//')

# Fix Docker socket permissions if it exists
if [ -S /var/run/docker.sock ]; then
  echo "Fixing Docker socket permissions..."
  sudo chmod 666 /var/run/docker.sock
fi

# Extract Owner and Repo from URL (e.g., https://github.com/owner/repo)
OWNER_REPO=$(echo "${REPO_URL}" | sed 's/.*github.com\///')

echo "Detected Repo: ${OWNER_REPO}"

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

# Set default Dagger version if not provided
DAGGER_VERSION=${DAGGER_VERSION:-"latest"}
RUNNER_LABELS=${RUNNER_LABELS:-"self-hosted"}
RUNNER_NAME=${RUNNER_NAME:-$(hostname)}
FULL_LABELS="${RUNNER_LABELS},dagger:${DAGGER_VERSION}"

echo "Configuring runner ${RUNNER_NAME} for ${REPO_URL} with labels: ${FULL_LABELS}"

# Navigate to runner directory
cd /home/runner

# 2. Register the runner using the retrieved Registration Token
./config.sh --url "${REPO_URL}" \
            --token "${REG_TOKEN}" \
            --name "${RUNNER_NAME}" \
            --labels "${FULL_LABELS}" \
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
}

# Trap signals for graceful shutdown
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup' EXIT

# Start the runner
./run.sh &
wait $!
