# Kubernetes Base Configuration

This directory contains shared Kubernetes resources that are used across all environments.

## Contents

- **namespace.yaml**: Defines the namespace for the application
- **persistent-volumes.yaml**: Defines persistent volume claims for stateful components
- **kustomization.yaml**: Kustomize configuration for base resources

## Namespace Configuration

The namespace defined in `namespace.yaml` serves as the foundation for all application components. Environment-specific namespaces are created in the overlays by appending the environment name (e.g., `tenant-service-dev`).

## Persistent Volume Configuration

The `persistent-volumes.yaml` file defines the following persistent volumes:

- **ssl-data**: For storing SSL certificates
- **redis-data**: For Redis persistence

## Usage

These base configurations are referenced by environment-specific overlays and should not be applied directly. Instead, use the overlay configurations:

```bash
# For development
kustomize build k8s/overlays/dev | kubectl apply -f -

# For production
kustomize build k8s/overlays/prod | kubectl apply -f -
```

Or use the deployment script:

```bash
./scripts/deploy-k8s.sh dev
```

## Customization

### Adding a New Persistent Volume

1. Edit `persistent-volumes.yaml` to add a new PVC definition
2. Update the `kustomization.yaml` file if necessary
3. Reference the new PVC in the component that needs it

### Modifying Namespace Configuration

The namespace template is used as a basis for environment-specific namespaces. If you need to add namespace-level configurations:

1. Edit `namespace.yaml` to add labels, annotations, or resource quotas
2. Make sure these changes are appropriate for all environments

## Best Practices

- Keep base configurations minimal and focused on shared resources
- Use overlays for environment-specific customizations
- Avoid hardcoding environment-specific values in base configurations
- Use variables like `${k8s_namespace}` that can be replaced in overlays 