FROM rust:1.81-slim as builder
WORKDIR /usr/src/app

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libclang-dev \
    clang \
    && rm -rf /var/lib/apt/lists/*

# Create a new empty shell project
RUN cargo init

# Copy only the dependency files first
COPY Cargo.toml Cargo.lock ./

# Build dependencies - this layer will be cached
RUN cargo build --release
    
# Now copy the source code
COPY src src/

# Build the application
RUN touch src/main.rs && cargo build --release

FROM gcr.io/distroless/base-debian12
COPY --from=builder /usr/src/app/target/release/tenant-service /usr/local/bin/
COPY .env /usr/local/bin/
WORKDIR /usr/local/bin

# Add non-root user permissions
USER nonroot:nonroot

EXPOSE 8080

# Add health check
HEALTHCHECK --interval=30s --timeout=3s \
    CMD ["/usr/local/bin/tenant-service", "--health-check"] || exit 1

CMD ["/usr/local/bin/tenant-service"] 