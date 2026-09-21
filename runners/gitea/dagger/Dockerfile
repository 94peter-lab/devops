FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    docker.io \
    docker-compose-v2 \
    gcc \
    unzip \
    sudo \
    jq \
    procps \
    ca-certificates \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Install gitea-runner / act_runner binary from Gitea releases
ARG ACT_RUNNER_VERSION=3.5.0
RUN ARCH=$(dpkg --print-architecture) \
    && case "$ARCH" in \
         amd64) ACT_ARCH=amd64 ;; \
         arm64) ACT_ARCH=arm64 ;; \
         *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; \
       esac \
    && ACT_RUNNER_VERSION="${ACT_RUNNER_VERSION#v}" \
    && (curl -fsSL "https://dl.gitea.com/gitea-runner/${ACT_RUNNER_VERSION}/gitea-runner-${ACT_RUNNER_VERSION}-linux-${ACT_ARCH}" -o /usr/local/bin/act_runner || \
        curl -fsSL "https://dl.gitea.com/act_runner/${ACT_RUNNER_VERSION}/act_runner-${ACT_RUNNER_VERSION}-linux-${ACT_ARCH}" -o /usr/local/bin/act_runner || \
        curl -fsSL "https://gitea.com/gitea/runner/releases/download/v${ACT_RUNNER_VERSION}/gitea-runner-${ACT_RUNNER_VERSION}-linux-${ACT_ARCH}" -o /usr/local/bin/act_runner || \
        curl -fsSL "https://gitea.com/gitea/act_runner/releases/download/v${ACT_RUNNER_VERSION}/act_runner-${ACT_RUNNER_VERSION}-linux-${ACT_ARCH}" -o /usr/local/bin/act_runner) \
    && chmod +x /usr/local/bin/act_runner \
    && ln -sf /usr/local/bin/act_runner /usr/local/bin/gitea-runner

# Install Dagger CLI
ARG DAGGER_VERSION=0.21.7
RUN curl -L https://dl.dagger.io/dagger/install.sh | DAGGER_VERSION=${DAGGER_VERSION} BIN_DIR=/usr/local/bin sh

# Install Infisical CLI (used by entrypoint.sh to fetch credentials when not set directly)
RUN curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | bash \
    && apt-get update && apt-get install -y --no-install-recommends infisical \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (LTS v20) required for running JavaScript Actions (e.g. actions/checkout)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Ensure runner user exists and has sudo access without password
RUN useradd -m -s /bin/bash runner \
    && echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner

# Prepare directories
RUN mkdir -p /etc/act_runner /data \
    && chown -R runner:runner /etc/act_runner /data

COPY config.yaml /etc/act_runner/config.yaml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chown runner:runner /etc/act_runner/config.yaml

USER runner
WORKDIR /data

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD ["pgrep", "act_runner"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
