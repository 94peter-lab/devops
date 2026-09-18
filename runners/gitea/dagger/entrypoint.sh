#!/bin/bash
set -e

INFISICAL_TOKEN=""

infisical_configured() {
  [ -n "$INFISICAL_CLIENT_ID" ] && [ -n "$INFISICAL_CLIENT_SECRET" ] && [ -n "$INFISICAL_PROJECT_ID" ]
}

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

GITEA_INSTANCE_URL=$(resolve GITEA_INSTANCE_URL)
if [ -z "$GITEA_INSTANCE_URL" ]; then
  GITEA_INSTANCE_URL=$(resolve GITEA_URL)
fi

GITEA_RUNNER_REGISTRATION_TOKEN=$(resolve GITEA_RUNNER_REGISTRATION_TOKEN)
if [ -z "$GITEA_RUNNER_REGISTRATION_TOKEN" ]; then
  GITEA_RUNNER_REGISTRATION_TOKEN=$(resolve GITEA_RUNNER_TOKEN)
fi

RUNNER_NAME="${RUNNER_NAME:-gitea-dagger-runner}"
RUNNER_LABELS="${RUNNER_LABELS:-ubuntu-latest:docker://gitea/runner-images:ubuntu-latest,self-hosted:host}"

# Check if .runner exists in /data
if [ ! -f /data/.runner ]; then
  if [ -z "$GITEA_INSTANCE_URL" ] || [ -z "$GITEA_RUNNER_REGISTRATION_TOKEN" ]; then
    echo "Error: GITEA_INSTANCE_URL and GITEA_RUNNER_REGISTRATION_TOKEN (or Infisical secrets) are required for registration."
    exit 1
  fi

  echo "Registering Gitea Runner with instance: ${GITEA_INSTANCE_URL}"
  act_runner register \
    --instance "${GITEA_INSTANCE_URL}" \
    --token "${GITEA_RUNNER_REGISTRATION_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --config /etc/act_runner/config.yaml \
    --no-interactive
fi

echo "Starting act_runner daemon..."
exec act_runner daemon --config /etc/act_runner/config.yaml
