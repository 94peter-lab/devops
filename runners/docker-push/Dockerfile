ARG RUNNER_VERSION=2.336.0
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

USER root

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    docker.io \
    sudo \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install Infisical CLI (used by entrypoint.sh to fetch GITHUB_TOKEN and
# registry credentials from Infisical when not set directly)
RUN curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | bash \
    && apt-get update && apt-get install -y --no-install-recommends infisical \
    && rm -rf /var/lib/apt/lists/*

# Install Docker Buildx as a CLI plugin (docker.io does not bundle it, unlike
# docker-ce). Needed for `docker buildx build`, e.g. multi-platform images.
ARG BUILDX_VERSION=0.19.3
RUN mkdir -p /usr/local/lib/docker/cli-plugins \
    && ARCH=$(dpkg --print-architecture) \
    && case "$ARCH" in \
         amd64) BUILDX_ARCH=amd64 ;; \
         arm64) BUILDX_ARCH=arm64 ;; \
         *) echo "Unsupported architecture for buildx: $ARCH" >&2; exit 1 ;; \
       esac \
    && BUILDX_VERSION="${BUILDX_VERSION#v}" \
    && curl -fsSL "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-${BUILDX_ARCH}" \
       -o /usr/local/lib/docker/cli-plugins/docker-buildx \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

# Ensure runner user has sudo access without password (required for Docker socket access)
RUN echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner

# Set up entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER runner

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
