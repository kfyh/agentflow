# Use Node.js 20 Debian Bookworm slim base image
FROM node:20-bookworm-slim

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install core system utilities, Python 3, and build essentials (but NO git)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    wget \
    jq \
    ripgrep \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Set up a Python virtual environment to avoid PEP 668 issues
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install global Node.js packages for web development
RUN npm install -g typescript ts-node eslint prettier webpack webpack-cli

# Setup workspace and permission owners for Python venv and node home
RUN mkdir -p /workspace /home/node/.gemini/antigravity-cli && \
    chown -R node:node /workspace /opt/venv /home/node

# Switch to the node user
USER node
WORKDIR /workspace

# Update PATH to include node user's local bin where agy installer puts the binary
ENV PATH="/home/node/.local/bin:$PATH"

# Install Antigravity CLI (agy) as the node user
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash

# Verify installed runtimes and binaries are working
RUN node --version && \
    npm --version && \
    tsc --version && \
    eslint --version && \
    prettier --version && \
    python3 --version && \
    pip --version && \
    agy --version

# Default entrypoint to bash (allows interactive mode)
CMD ["/bin/bash"]
