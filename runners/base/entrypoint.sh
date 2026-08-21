#!/bin/bash
set -e

# Validate scope: exactly one of REPO_URL (repo-level runner) or ORG_URL
# (org-level runner) must be set.
if [ -n "$REPO_URL" ] && [ -n "$ORG_URL" ]; then
  echo "Error: Set only one of REPO_URL or ORG_URL, not both."
  exit 1
fi

if [ -n "$REPO_URL" ]; then
  SCOPE="repo"
  TARGET_URL=$(echo "${REPO_URL}" | sed 's/\.git$//' | sed 's/\/$//')
  OWNER_REPO=$(echo "${TARGET_URL}" | sed 's/.*github.com\///')
  API_BASE="https://api.github.com/repos/${OWNER_REPO}"
  echo "Detected Repo: ${OWNER_REPO}"
elif [ -n "$ORG_URL" ]; then
  SCOPE="org"
  TARGET_URL=$(echo "${ORG_URL}" | sed 's/\/$//')
  ORG=$(echo "${TARGET_URL}" | sed 's/.*github.com\///')
  API_BASE="https://api.github.com/orgs/${ORG}"
  echo "Detected Org: ${ORG}"
else
  echo "Error: Either REPO_URL or ORG_URL must be set."
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

# Fix Docker socket permissions if it exists
if [ -S /var/run/docker.sock ]; then
  echo "Fixing Docker socket permissions..."
  sudo chmod 666 /var/run/docker.sock
fi

# 1. Get a Registration Token via API
# Note: for org-level runners, GITHUB_TOKEN needs the "admin:org" scope
# (classic PAT) or the Organization permission "Self-hosted runners: Read
# and write" (fine-grained PAT / GitHub App installation token). For
# repo-level runners, it needs the "repo" scope or the repo Administration
# permission.
echo "Fetching registration token from GitHub (${SCOPE}-level)..."
REG_TOKEN=$(curl -s -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "${API_BASE}/actions/runners/registration-token" | jq -r '.token')

if [ "$REG_TOKEN" == "null" ] || [ -z "$REG_TOKEN" ]; then
  echo "Error: Failed to get registration token. Check your GITHUB_TOKEN permissions and ${SCOPE^^}_URL."
  exit 1
fi

# Set default Dagger version if not provided
DAGGER_VERSION=${DAGGER_VERSION:-"latest"}
RUNNER_LABELS=${RUNNER_LABELS:-"self-hosted"}
RUNNER_NAME=${RUNNER_NAME:-$(hostname)}
FULL_LABELS="${RUNNER_LABELS},dagger:${DAGGER_VERSION}"

echo "Configuring runner ${RUNNER_NAME} for ${TARGET_URL} with labels: ${FULL_LABELS}"

# Navigate to runner directory
cd /home/runner

# 2. Register the runner using the retrieved Registration Token
./config.sh --url "${TARGET_URL}" \
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
      "${API_BASE}/actions/runners/remove-token" | jq -r '.token')

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
