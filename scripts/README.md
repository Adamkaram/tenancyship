# Management Scripts

This directory contains scripts for managing the application and its infrastructure.

## all-in-one.sh

The `all-in-one.sh` script is a comprehensive management tool that provides a unified interface for all aspects of the application:

- Local development
- Kubernetes deployment
- Infrastructure management with Terraform
- Monitoring and troubleshooting

### Features

- **Interactive Menu System**: User-friendly menu interface with color coding
- **Command Line Interface**: Can be used in scripts and automation
- **Multi-Environment Support**: Handles development and production environments
- **Component Management**: Unified interface for tenant service, nginx, and redis
- **Infrastructure Management**: Integrates with Terraform for cloud resources
- **Local Development Tools**: Run Go, Rust, and Podman components locally

### Usage

#### Interactive Mode

```bash
# Make the script executable (if not already)
chmod +x scripts/all-in-one.sh

# Run in interactive mode
./scripts/all-in-one.sh
```

#### Command Line Mode

```bash
# General syntax
./scripts/all-in-one.sh <command> [options]
```

#### Convenient Symlink

For easier access, create a symlink in the project root:

```bash
ln -sf scripts/all-in-one.sh ../manage
```

Then you can use:

```bash
./manage
# or
./manage <command> [options]
```

### Common Commands

```bash
# Deploy to development with Kustomize
./scripts/all-in-one.sh kustomize dev

# Deploy to development with Terraform
./scripts/all-in-one.sh deploy dev

# Run the local Go application
./scripts/all-in-one.sh run-local

# Run the Rust tenant service
./scripts/all-in-one.sh run-rust

# Deploy locally with docker-compose
./scripts/all-in-one.sh deploy-local

# Show Kubernetes resources
./scripts/all-in-one.sh status dev

# Get pod logs
./scripts/all-in-one.sh logs dev

# Open shell in a pod
./scripts/all-in-one.sh shell dev

# Restart deployments
./scripts/all-in-one.sh restart dev

# Clean up resources
./scripts/all-in-one.sh cleanup dev
```

### Development and Customization

The script is organized into logical sections:

1. **Helper Functions**: Common utility functions
2. **Kubernetes Deployment Functions**: Kustomize and direct k8s operations
3. **Terraform Functions**: Infrastructure management
4. **Local Development Functions**: Running Go, Rust, and docker-compose
5. **Kubernetes Management Functions**: Resource monitoring and management
6. **Menu System**: Interactive menu interface
7. **Command Line Interface**: Command processing

To extend the script:

1. Add new functions to the appropriate section
2. Update the menu system if needed
3. Add new command-line options to the CLI handler

For more detailed information, see [README-all-in-one.md](README-all-in-one.md).

## Legacy Scripts (Replaced)

The following scripts have been consolidated into all-in-one.sh:

- `tenant-service.sh`: Original tenant service management
- `deploy-k8s.sh`: Kubernetes deployment
- `run.sh`: Run Go application locally
- `run_rust.sh`: Run Rust tenant service locally
- `deploy.sh`: Deploy with docker-compose locally

All functionality from these scripts is now available in the all-in-one script with an improved interface.