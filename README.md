# tenancyship
core utility for multi-tenancy saas projects with go&amp;nginx

![Uploading ChatGPT Image Apr 4, 2025, 09_45_53 PM.png…]()


1- db service with rust axum and surrealdb
2- go in general
3- podman

# Tenant Service

This project implements a tenant service using Rust, SurrealDB, and Kubernetes, with Terraform for infrastructure management.

## Project Structure
```
tenancyship/
├── db-service/                   # SurrealDB service with Rust/Axum
│   ├── src/                      # Rust source code
│   ├── Cargo.toml               # Rust dependencies
│   └── Cargo.lock               # Rust lockfile
├── tenant-service/              # Go tenant management service
│   ├── go.mod                   # Go module definition
│   ├── go.sum                   # Go dependencies checksum
│   ├── cmd/                     # Command line applications
│   │   └── server/             # Main server application
│   │       └── main.go         # Server entrypoint
│   ├── internal/               # Private application code
│   │   ├── api/               # API handlers and routes
│   │   ├── models/            # Data models
│   │   └── services/          # Business logic
│   └── pkg/                    # Public packages
│       └── tenant/            # Tenant management package
├── terraform/                  # Infrastructure as code
│   ├── main.tf                # Main Terraform configuration
│   ├── variables.tf           # Variable definitions
│   └── secrets/               # Environment-specific variables
│       ├── template.tfvars    # Template for environment variables
│       ├── dev.tfvars         # Development environment variables
│       └── prod.tfvars        # Production environment variables
├── k8s/                       # Kubernetes manifests
│   ├── base/                  # Base configurations
│   │   ├── namespace.yaml     # Namespace definition
│   │   └── persistent-volumes.yaml # Persistent volume definitions
│   ├── tenant-service/        # Tenant service configurations
│   │   └── base/              # Base tenant service configs
│   ├── nginx/                 # Nginx configurations
│   │   └── base/              # Base nginx configs
│   ├── redis/                 # Redis configurations
│   │   └── base/              # Base redis configs
│   └── overlays/              # Environment-specific configurations
│       ├── dev/               # Development environment
│       └── prod/              # Production environment
└── scripts/                   # Utility scripts
    └── all-in-one.sh          # All-in-one management script
```

## Prerequisites

- Docker or Podman
- Kubernetes cluster (or Minikube for local development)
- Terraform
- kubectl
- kustomize (installed automatically by the management script)

## Setup and Management

This project includes a comprehensive all-in-one management script that handles all aspects of development, deployment, and management.

### Quick Start

```bash
# Make the script executable
chmod +x scripts/all-in-one.sh

# Create a convenient symlink
ln -sf scripts/all-in-one.sh ./manage

# Run the interactive menu
./manage
```

### Interactive Menu

The management script provides an interactive menu system with the following options:

1. **Development Environment**
   - Deploy using Kustomize
   - Deploy using Terraform + K8s
   - Show Kubernetes resources
   - Get pod logs
   - Restart deployments
   - Shell into a pod
   - Check SSL certificates
   - Clean up resources

2. **Production Environment**
   - Same options as development (with confirmation prompts for safety)

3. **Local Development**
   - Run application with Go or Podman
   - Run Rust tenant service
   - Deploy locally using docker-compose

4. **Tools & Setup**
   - Install required tools
   - Set up development environment
   - Set up production environment

### Command Line Usage

You can also use the script directly with commands:

```bash
# General syntax
./manage <command> [options]
```

Common commands:

```bash
# Install required tools
sudo ./manage install

# Set up development environment
./manage setup dev

# Deploy to development environment
./manage deploy dev

# Deploy to development with Kustomize
./manage kustomize dev

# Run local application (Go or Podman)
./manage run-local

# Run Rust tenant service
./manage run-rust

# Deploy locally with docker-compose
./manage deploy-local

# Check status of deployments
./manage status dev

# View logs from pods
./manage logs dev

# Open shell in a pod
./manage shell dev

# Check SSL certificates
./manage ssl-status dev

# Restart deployments
./manage restart dev

# Clean up resources
./manage cleanup dev
```

## Kubernetes Structure

The Kubernetes configurations follow a Kustomize-based structure:

- **Base**: Contains shared resources (namespace, persistent volumes)
- **Component Directories**: Component-specific configurations:
  - `tenant-service`: Main backend service
  - `nginx`: Frontend proxy with SSL termination
  - `redis`: Caching layer
- **Overlays**: Environment-specific configurations
  - `dev`: Development environment settings
  - `prod`: Production environment settings with higher replica counts

## Local Development

For local development, you can use:

```bash
# Run the Go application directly
./manage run-local
# Select option 1 when prompted

# Run with docker-compose/podman-compose
./manage run-local
# Select option 2 when prompted

# Run the Rust tenant service
./manage run-rust

# Deploy locally with all services
./manage deploy-local
```

## Secret Management

This project uses a multi-layered approach to secret management:

1. **Development**: Environment variables or ConfigMaps
2. **Kubernetes**: Kubernetes Secrets mounted as files
3. **Terraform**: Terraform variables for infrastructure secrets

## Customization

### Adding New Components

1. Create a new directory in `k8s/` for your component
2. Add base manifests in a `base/` subdirectory
3. Update overlays to include your component
4. Deploy using `./manage kustomize dev`

### Adding New Environments

1. Create a new directory in `k8s/overlays/` for your environment
2. Copy files from an existing environment as templates
3. Set up Terraform variables: `./manage setup <new-env>`
4. Deploy to the new environment: `./manage deploy <new-env>`

## Troubleshooting

The management script includes built-in troubleshooting capabilities:

```bash
# Check deployment status
./manage status dev

# View pod logs
./manage logs dev

# Shell into a pod for debugging
./manage shell dev
```

Common issues and solutions:

1. **Connection to database fails**: Check the database credentials in your ConfigMap or environment variables
2. **Kubernetes pods not starting**: Check pod status and logs with `./manage status dev` and `./manage logs dev`
3. **Terraform errors**: Ensure your `.tfvars` file has all required variables

For more detailed troubleshooting, check the README files in each component directory:
- `k8s/README.md`: Overview of Kubernetes structure
- `k8s/tenant-service/README.md`: Tenant service details
- `k8s/nginx/README.md`: Nginx proxy details
- `k8s/redis/README.md`: Redis cache details
- `scripts/README-all-in-one.md`: Detailed usage of the management script


