# tenancyship
core utility for multi-tenancy saas projects with go&amp;nginx

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
│   ├── namespace.yaml         # Namespace definition
│   ├── deployment.yaml        # Deployment configuration
│   └── service.yaml          # Service configuration
└── scripts/                   # Utility scripts
    └── tenant-service.sh      # All-in-one management script
```

## Prerequisites

- Docker
- Kubernetes cluster (or Minikube for local development)
- Terraform
- kubectl
- Vault (optional, for enhanced secret management)

## Setup

### 1. Install Required Tools

```bash
sudo ./scripts/tenant-service.sh install
```

This will install Terraform, kubectl, and Vault on your system.

### 2. Set Up Environment

```bash
./scripts/tenant-service.sh setup dev  # For development
# OR
./scripts/tenant-service.sh setup prod  # For production
```

This will create environment-specific variable files in `terraform/secrets/`. Edit these files to set your specific values for SurrealDB, Vault, and Kubernetes.

### 3. Deploy the Infrastructure

```bash
./scripts/tenant-service.sh deploy dev  # For development
# OR
./scripts/tenant-service.sh deploy prod  # For production
```

This will:
1. Initialize Terraform
2. Apply the Terraform configuration with your environment variables
3. Create the Kubernetes namespace, deployment, and service

## Management Commands

The `tenant-service.sh` script provides a unified interface for common operations:

### Deployment Management

```bash
# Deploy to an environment
./scripts/tenant-service.sh deploy <env>

# Plan changes without applying
./scripts/tenant-service.sh deploy <env> plan

# Destroy infrastructure
./scripts/tenant-service.sh deploy <env> destroy
```

Where `<env>` is either `dev` or `prod`.

### Status Checking

```bash
# Check deployment status
./scripts/tenant-service.sh status <env>
```

This shows the status of pods, services, deployments, and secrets in your environment.

### Log Viewing

```bash
# View logs from the tenant service
./scripts/tenant-service.sh logs <env>
```

## Secret Management

This project uses a multi-layered approach to secret management:

1. **Development**: Environment variables or `.env` files
2. **Kubernetes**: Kubernetes Secrets mounted as files
3. **Vault**: HashiCorp Vault for centralized secret management

The application will automatically detect and use the appropriate method based on its environment.

## Customization

### Adding New Environments

1. Create a new environment file: `./scripts/tenant-service.sh setup <new-env>`
2. Edit the generated file at `terraform/secrets/<new-env>.tfvars`
3. Deploy to the new environment: `./scripts/tenant-service.sh deploy <new-env>`

### Changing SurrealDB Configuration

Edit your environment variables file (`terraform/secrets/<env>.tfvars`) and update:

surrealdb_url = "wss://your-new-instance"
surrealdb_user = "new-user"
surrealdb_password = "new-password"
surrealdb_ns = "new-namespace"
surrealdb_db = "new-database"

Then redeploy: `./scripts/tenant-service.sh deploy <env>`

## Security Best Practices

1. Never commit actual secrets to git
2. Use different credentials for each environment
3. Rotate secrets regularly
4. Use strong passwords
5. Consider a secrets management service in production
6. Use encrypted communication
7. Consider using Vault's dynamic secrets capabilities

## Troubleshooting

### Common Issues

1. **Connection to SurrealDB fails**: Check the SurrealDB URL and credentials in your environment file.
2. **Kubernetes pods not starting**: Check the pod status and logs with `./scripts/tenant-service.sh status <env>` and `./scripts/tenant-service.sh logs <env>`.
3. **Terraform errors**: Ensure your `.tfvars` file has all required variables.

For more detailed troubleshooting, check the logs of the specific components.


