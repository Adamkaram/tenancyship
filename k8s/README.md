# Kubernetes Deployment Structure

This directory contains the Kubernetes manifests for deploying the tenant service and its dependencies.

## Architecture Overview

The application consists of the following components:

- **Tenant Service**: The main backend service written in Go/Rust that handles tenant management
- **Nginx SSL Proxy**: Frontend proxy that handles SSL termination and routing
- **Redis**: Caching layer for improved performance

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
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── configmap.yaml
│       └── pvc.yaml
└── overlays/              # Environment-specific configurations
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── tenant-service-replicas.yaml
    │   ├── nginx-replicas.yaml
    │   └── redis-replicas.yaml
    └── prod/
        ├── kustomization.yaml
        ├── tenant-service-replicas.yaml
        ├── nginx-replicas.yaml
        └── redis-replicas.yaml
```

## Development Workflow

### Prerequisites
- Kubernetes cluster (minikube, k3s, or cloud provider)
- kubectl
- kustomize (installed automatically by the deployment script)

### Local Development
1. Start your local Kubernetes cluster:
   ```bash
   minikube start
   ```

2. Build your local images:
   ```bash
   ./scripts/build-images.sh
   ```

3. Deploy to development environment:
   ```bash
   ./scripts/deploy-k8s.sh dev
   ```

### Production Deployment
1. Build and push images to your container registry:
   ```bash
   ./scripts/build-and-push.sh
   ```

2. Deploy to production environment:
   ```bash
   ./scripts/deploy-k8s.sh prod
   ```

## Kustomize Overview

This project uses Kustomize for managing Kubernetes manifests:

- **Base Layer**: Contains shared resources across environments
- **Component Layers**: Component-specific configurations (tenant-service, nginx, redis)
- **Overlay Layer**: Environment-specific configurations (dev, prod)

To view the fully rendered manifests without applying them:
```bash
kustomize build k8s/overlays/dev
```

## Configuration Management

Configuration is managed through ConfigMaps:

- **tenant-service-config**: Application settings for tenant service
- **nginx-config**: Nginx server configuration
- **redis-config**: Redis server settings

Environment-specific configurations are managed in the overlay directories using configMapGenerator.

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending state**:
   ```bash
   kubectl describe pod <pod-name> -n tenant-service-dev
   ```
   Common causes: PersistentVolume issues, resource constraints

2. **Service not accessible**:
   ```bash
   kubectl get svc -n tenant-service-dev
   kubectl port-forward svc/nginx-ssl-proxy 8080:80 -n tenant-service-dev
   ```

3. **Container crash loops**:
   ```bash
   kubectl logs <pod-name> -n tenant-service-dev
   ```

### Debugging Tools

- **Shell access to pods**:
  ```bash
  kubectl exec -it <pod-name> -n tenant-service-dev -- /bin/sh
  ```

- **Network debugging**:
  ```bash
  kubectl run netshoot --rm -it --image nicolaka/netshoot -- /bin/bash
  ```

## Security Considerations

- Secrets are managed through Kubernetes Secrets
- TLS termination happens at the Nginx layer
- Network policies should be implemented to restrict pod-to-pod communication

## Maintenance Tasks

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

### Upgrading Kubernetes Version
When upgrading Kubernetes version:
1. Test in development first
2. Check for deprecated APIs
3. Update manifests if necessary
4. Apply changes gradually

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

### Redis Cache
- Resource limits: 500m CPU, 256Mi memory
- Health check endpoint: /health
- Persistent volume for data persistence

## Monitoring
The deployments include health checks that can be monitored using:
```