# All-in-One Management Script

This is a comprehensive management script that combines the functionality of all other scripts into a single, powerful utility for managing your application and Kubernetes deployments.

## Features

- **Unified Interface**: Handles both local development and Kubernetes deployments
- **Interactive Menu System**: Easy-to-navigate menus with color coding
- **Command Line Support**: Can be used both interactively and via command line arguments
- **Multi-Environment Support**: Handles dev and prod environments with appropriate safety checks
- **Comprehensive Functionality**:
  - Kubernetes deployment (using Kustomize or direct application)
  - Infrastructure management with Terraform
  - Local development environment management
  - Monitoring and management of deployed services
  - System setup and tool installation

## Usage

### Interactive Mode

```bash
# Make the script executable (if not already)
chmod +x scripts/all-in-one.sh

# Run in interactive mode
./scripts/all-in-one.sh
```

The interactive menu provides the following options:

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
   - All the same options as development (with confirmation prompts)

3. **Local Development**
   - Run application (run.sh)
   - Run Rust service (run_rust.sh)
   - Deploy locally (deploy.sh)

4. **Tools & Setup**
   - Install required tools
   - Set up development environment
   - Set up production environment

### Command Line Mode

```bash
# General syntax
./scripts/all-in-one.sh <command> [options]
```

#### Available Commands

| Command | Description | Example |
|---------|-------------|---------|
| `menu` | Show interactive menu | `./scripts/all-in-one.sh menu` |
| `deploy <env> [action]` | Manage infrastructure deployment | `./scripts/all-in-one.sh deploy dev apply` |
| `kustomize <env>` | Deploy using Kustomize | `./scripts/all-in-one.sh kustomize dev` |
| `install` | Install required tools | `sudo ./scripts/all-in-one.sh install` |
| `setup <env>` | Set up environment | `./scripts/all-in-one.sh setup dev` |
| `status <env>` | Check deployment status | `./scripts/all-in-one.sh status dev` |
| `logs <env>` | View logs from pods | `./scripts/all-in-one.sh logs dev` |
| `ssl-status <env>` | Check SSL certificates | `./scripts/all-in-one.sh ssl-status dev` |
| `shell <env>` | Open shell in a pod | `./scripts/all-in-one.sh shell dev` |
| `restart <env>` | Restart deployments | `./scripts/all-in-one.sh restart dev` |
| `cleanup <env>` | Clean up resources | `./scripts/all-in-one.sh cleanup dev` |
| `run-local` | Run the application | `./scripts/all-in-one.sh run-local` |
| `run-rust` | Run Rust service | `./scripts/all-in-one.sh run-rust` |
| `deploy-local` | Deploy locally | `./scripts/all-in-one.sh deploy-local` |
| `help` | Show help message | `./scripts/all-in-one.sh help` |

## Advantages Over Individual Scripts

This unified script replaces the following scripts:
- `manage.sh`: General management script
- `deploy-k8s.sh`: Kubernetes deployment script
- `tenant-service.sh`: Tenant service management script
- `run.sh`: Local application runner
- `run_rust.sh`: Rust service runner
- `deploy.sh`: Local deployment script

Benefits:
1. **Reduced Complexity**: One script to remember instead of multiple
2. **Consistent Interface**: Same pattern for all operations
3. **Improved Error Handling**: Better validation and error reporting
4. **Enhanced Safety**: Confirmations for critical operations
5. **Richer Functionality**: Combines all features with additional capabilities

## Configuration

The script automatically detects and uses:
- Kubernetes configurations in the `k8s/` directory
- Terraform configurations in the `terraform/` directory
- Local development scripts in the project root

## Requirements

- Bash shell
- For Kubernetes operations: kubectl (installed automatically)
- For Terraform operations: terraform (installed automatically)
- For Kustomize operations: kustomize (installed automatically)

## Customization

If you need to modify the script:
- **Add a new function**: Add it in the appropriate section
- **Add a new menu item**: Update the relevant menu function
- **Add a new command line option**: Update the command line handler at the end

## Examples

**1. Deploy to Development:**
```bash
./scripts/all-in-one.sh deploy dev
```

**2. Check Status of Production:**
```bash
./scripts/all-in-one.sh status prod
```

**3. Run Locally:**
```bash
./scripts/all-in-one.sh run-local
```

**4. Interactive Menu:**
```bash
./scripts/all-in-one.sh
# Then navigate through menus
``` 