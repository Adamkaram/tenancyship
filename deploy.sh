#!/bin/bash

# Install uv if not already installed
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create and activate a virtual environment
uv venv
source .venv/bin/activate  # On Unix/macOS

# Install podman-compose
uv pip install podman-compose

# Clean up existing containers and images
podman-compose down --volumes
podman system prune -f

# Build and run with podman-compose
podman-compose build --no-cache
podman-compose up

