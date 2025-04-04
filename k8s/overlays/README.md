# Kubernetes Environment Overlays

This directory contains environment-specific Kubernetes configurations using Kustomize overlays.

## Directory Structure

```
overlays/
├── dev/                    # Development environment
│   ├── kustomization.yaml
│   ├── tenant-service-replicas.yaml
│   ├── nginx-replicas.yaml
│   └── redis-replicas.yaml
└── prod/                   # Production environment
    ├── kustomization.yaml
    ├── tenant-service-replicas.yaml
    ├── nginx-replicas.yaml
    └── redis-replicas.yaml
```

## Environment Configuration

### Development (dev)

The development environment is configured for:
- Single replicas of each component
- Debug logging enabled
- Development-specific configurations
- Lighter resource constraints

Deploy with:
```bash
./scripts/deploy-k8s.sh dev
```

### Production (prod)

The production environment is configured for:
- Multiple replicas for high availability
- Production logging levels
- Stricter resource constraints
- Production-specific security settings

Deploy with:
```bash
./scripts/deploy-k8s.sh prod
```

## Customization

### Adding Environment-Specific Configuration

1. Create a new file in the environment directory (e.g., `dev/my-config.yaml`)
2. Add the file to the `patchesStrategicMerge` section in the environment's `kustomization.yaml`

### Creating a New Environment

To create a new environment (e.g., staging):

1. Create a new directory: `mkdir -p overlays/staging`
2. Copy the kustomization and patches from an existing environment:
   ```bash
   cp -r overlays/dev/* overlays/staging/
   ```
3. Modify the configurations as needed
4. Update the deployment script to support the new environment

## ConfigMap Generation

Environment-specific ConfigMaps are generated using the `configMapGenerator` in each environment's `kustomization.yaml`. For example:

```yaml
configMapGenerator:
  - name: tenant-service-config
    behavior: merge
    literals:
      - environment_type=development
      - log_level=debug
```

This allows for environment-specific configuration values.

## Patching Resources

Resources are patched using strategic merge patches. For example, to change the number of replicas:

```yaml
# tenant-service-replicas.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tenant-service
spec:
  replicas: 3
```

## Namespace Configuration

Each environment uses a dedicated namespace (e.g., `tenant-service-dev`, `tenant-service-prod`) to ensure isolation between environments. 