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

INFISICAL_TOKEN=""

infisical_configured() {
  [ -n "$INFISICAL_CLIENT_ID" ] && [ -n "$INFISICAL_CLIENT_SECRET" ] && [ -n "$INFISICAL_PROJECT_ID" ]
}

# Logs in to Infisical at most once per container start and caches the
# resulting token in $INFISICAL_TOKEN.
infisical_login_once() {
  if [ -n "$INFISICAL_TOKEN" ]; then
    return
  fi

  INFISICAL_TOKEN=$(infisical login \
    --method=universal-auth \
    --client-id="${INFISICAL_CLIENT_ID}" \
    --client-secret="${INFISICAL_CLIENT_SECRET}" \
    --silent --plain) || true

  if [ -z "$INFISICAL_TOKEN" ]; then
    echo "Error: Failed to authenticate with Infisical (check INFISICAL_CLIENT_ID/INFISICAL_CLIENT_SECRET)."
    exit 1
  fi
}

# Fetches a single secret from Infisical, named exactly like the variable
# it backs (e.g. secret "GITHUB_APP_ID" for $GITHUB_APP_ID). Prints nothing
# (rather than erroring) if the secret doesn't exist, so callers can treat
# this as an optional lookup.
infisical_get() {
  local secret_name=$1
  infisical_login_once
  infisical secrets get "${secret_name}" \
    --projectId="${INFISICAL_PROJECT_ID}" \
    --env="${INFISICAL_ENV:-prod}" \
    --path="${INFISICAL_SECRET_PATH:-/}" \
    --token="${INFISICAL_TOKEN}" \
    --plain 2>/dev/null || true
}

# Resolves a plain (single-line) value: the environment variable of the
# same name if set, otherwise an Infisical secret of the same name (if
# Infisical is configured).
resolve() {
  local var_name=$1
  local current="${!var_name}"
  if [ -n "$current" ]; then
    printf '%s' "$current"
    return
  fi
  if infisical_configured; then
    infisical_get "$var_name"
  fi
}

# Resolves the GitHub App private key (a multi-line PEM). Checked in order:
# 1. GITHUB_APP_PRIVATE_KEY - a literal PEM already in the environment.
# 2. GITHUB_APP_PRIVATE_KEY_BASE64 - a base64-encoded PEM, for env vars
#    (e.g. Coolify) that don't handle multi-line values well.
# 3. Infisical secret "GITHUB_APP_PRIVATE_KEY" - stored as the raw PEM,
#    since Infisical handles multi-line secret values natively.
resolve_github_app_private_key() {
  if [ -n "$GITHUB_APP_PRIVATE_KEY" ]; then
    printf '%s' "$GITHUB_APP_PRIVATE_KEY"
    return
  fi
  if [ -n "$GITHUB_APP_PRIVATE_KEY_BASE64" ]; then
    printf '%s' "$GITHUB_APP_PRIVATE_KEY_BASE64" | base64 -d
    return
  fi
  if infisical_configured; then
    infisical_get "GITHUB_APP_PRIVATE_KEY"
  fi
}

base64url() {
  base64 -w0 | tr '+/' '-_' | tr -d '='
}

# Signs a JWT for GITHUB_APP_ID and exchanges it for an installation access
# token scoped to GITHUB_APP_INSTALLATION_ID. Installation tokens expire
# after 1 hour, so this is called again from cleanup() with a fresh JWT
# rather than reusing the token minted here at startup.
mint_app_installation_token() {
  local now iat exp header payload unsigned signature jwt

  now=$(date +%s)
  iat=$((now - 60))
  exp=$((now + 540))

  header=$(printf '{"alg":"RS256","typ":"JWT"}' | base64url)
  payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$iat" "$exp" "$GITHUB_APP_ID" | base64url)
  unsigned="${header}.${payload}"
  signature=$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign <(printf '%s\n' "$GITHUB_APP_PRIVATE_KEY") -binary | base64url)
  jwt="${unsigned}.${signature}"

  curl -s -X POST \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens" | jq -r '.token'
}

# Resolve credentials. Every value below is looked up as: the environment
# variable directly, else (if Infisical is configured) an Infisical secret
# of the exact same name. Priority: GitHub App (if fully resolved) beats a
# resolved GITHUB_TOKEN.
GITHUB_APP_ID=$(resolve GITHUB_APP_ID)
GITHUB_APP_PRIVATE_KEY=$(resolve_github_app_private_key)
GITHUB_APP_INSTALLATION_ID=$(resolve GITHUB_APP_INSTALLATION_ID)
GITHUB_TOKEN=$(resolve GITHUB_TOKEN)

USE_GITHUB_APP=false

if [ -n "$GITHUB_APP_ID" ] && [ -n "$GITHUB_APP_PRIVATE_KEY" ] && [ -n "$GITHUB_APP_INSTALLATION_ID" ]; then
  if [ -n "$GITHUB_TOKEN" ]; then
    echo "Both GITHUB_TOKEN and GitHub App credentials are available; using the GitHub App (it takes priority)."
  fi

  echo "Minting a GitHub App installation access token..."
  GITHUB_TOKEN=$(mint_app_installation_token)

  if [ "$GITHUB_TOKEN" == "null" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: Failed to exchange the GitHub App JWT for an installation access token. Check GITHUB_APP_ID / GITHUB_APP_PRIVATE_KEY(_BASE64) / GITHUB_APP_INSTALLATION_ID."
    exit 1
  fi
  USE_GITHUB_APP=true
fi

if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: No GitHub credentials available. Set GITHUB_TOKEN directly, GITHUB_APP_ID / GITHUB_APP_PRIVATE_KEY(_BASE64) / GITHUB_APP_INSTALLATION_ID for a GitHub App, or store any of these as Infisical secrets of the same name (with INFISICAL_CLIENT_ID / INFISICAL_CLIENT_SECRET / INFISICAL_PROJECT_ID set)."
  exit 1
fi

# Fix Docker socket permissions if it exists
if [ -S /var/run/docker.sock ]; then
  echo "Fixing Docker socket permissions..."
  sudo chmod 666 /var/run/docker.sock
fi

# 1. Get a Registration Token via API
# Note: for org-level runners, the credentials need the "admin:org" scope
# (classic PAT) or the Organization permission "Self-hosted runners: Read
# and write" (fine-grained PAT / GitHub App), instead of the repo-level
# "repo" scope / Administration permission.
echo "Fetching registration token from GitHub (${SCOPE}-level)..."
REG_TOKEN=$(curl -s -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "${API_BASE}/actions/runners/registration-token" | jq -r '.token')

if [ "$REG_TOKEN" == "null" ] || [ -z "$REG_TOKEN" ]; then
  echo "Error: Failed to get registration token. Check your credentials' permissions and ${SCOPE^^}_URL."
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

    local removal_token="$GITHUB_TOKEN"
    if [ "$USE_GITHUB_APP" = true ]; then
        echo "Refreshing GitHub App installation token for cleanup..."
        local fresh_token
        fresh_token=$(mint_app_installation_token)
        if [ "$fresh_token" != "null" ] && [ -n "$fresh_token" ]; then
            removal_token="$fresh_token"
        else
            echo "Warning: Failed to refresh the installation token; the original one from startup may have expired."
        fi
    fi

    # Get a fresh removal token
    REMOVE_TOKEN=$(curl -s -X POST \
      -H "Authorization: token ${removal_token}" \
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
