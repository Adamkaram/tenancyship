# Kubernetes Deployment Structure

This directory contains the Kubernetes manifests for deploying the tenant service and its dependencies.

## Directory Structure

```
k8s/
├── base/                    # Base configurations
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── persistent-volumes.yaml
├── tenant-service/         # Tenant service specific configurations
│   └── base/
│       ├── kustomization.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       └── configmap.yaml
├── nginx/                  # Nginx SSL proxy configurations
│   └── base/
│       ├── kustomization.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       └── configmap.yaml
├── redis/                  # Redis cache configurations
│   └── base/
│       ├── kustomization.yaml
│       └── deployment.yaml
└── overlays/              # Environment-specific configurations
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── tenant-service-replicas.yaml
    │   └── nginx-replicas.yaml
    └── prod/
        ├── kustomization.yaml
        ├── tenant-service-replicas.yaml
        └── nginx-replicas.yaml
```

## Deployment

The deployment process uses Kustomize to manage different environments. To deploy:

1. Make sure you have the required tools installed:
   - kubectl
   - kustomize (will be installed automatically if missing)

2. Deploy to development:
   ```bash
   ./scripts/deploy-k8s.sh dev
   ```

3. Deploy to production:
   ```bash
   ./scripts/deploy-k8s.sh prod
   ```

## Features

- Environment-specific configurations using Kustomize overlays
- Resource limits and requests for all containers
- Health checks (readiness and liveness probes)
- ConfigMap-based configuration management
- Persistent volume management
- SSL/TLS support through Nginx
- Namespace isolation
- Redis caching layer

## Configuration

### Tenant Service
- Resource limits: 500m CPU, 512Mi memory
- Health check endpoint: /health
- Environment variables managed through ConfigMap

### Nginx SSL Proxy
- Resource limits: 500m CPU, 256Mi memory
- Health check endpoint: /health
- SSL/TLS configuration through ConfigMap
- Persistent volume for SSL certificates

### Redis Cache
- Resource limits: 500m CPU, 256Mi memory
- Health check endpoint: /health
- Persistent volume for data persistence

## Maintenance

### Updating Container Images
To update container images, modify the image tags in the respective deployment files:
- `tenant-service/base/deployment.yaml`
- `nginx/base/deployment.yaml`
- `redis/base/deployment.yaml`

### Scaling
To scale the number of replicas, modify the `replicas` field in the environment-specific overlay files:
- `overlays/dev/tenant-service-replicas.yaml`
- `overlays/dev/nginx-replicas.yaml`
- `overlays/prod/tenant-service-replicas.yaml`
- `overlays/prod/nginx-replicas.yaml`

### Monitoring
The deployments include health checks that can be monitored using:
```bash
kubectl get pods -n tenant-service-{env} -w
``` 