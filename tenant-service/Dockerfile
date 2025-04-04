# Use cargo-chef to plan dependencies
FROM lukemathwalker/cargo-chef:latest-rust-1 AS chef
WORKDIR /app

# Plan the dependencies
FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# Build the dependencies and application
FROM chef AS builder 
COPY --from=planner /app/recipe.json recipe.json
# Build dependencies - this is the caching Docker layer!
RUN cargo chef cook --release --recipe-path recipe.json

# Build application
COPY . .
RUN cargo build --release --bin tenant-service

# Runtime stage
FROM debian:bookworm-slim AS runtime
WORKDIR /app

# Install necessary runtime libraries
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy the binary
COPY --from=builder /app/target/release/tenant-service /usr/local/bin

# Create and use non-root user
RUN useradd -ms /bin/bash nonroot
USER nonroot

# Expose the port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:8080/ || exit 1

# Run the service
CMD ["/usr/local/bin/tenant-service"]
