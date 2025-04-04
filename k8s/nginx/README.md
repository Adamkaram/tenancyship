# Nginx SSL Proxy in Kubernetes

This directory contains the Kubernetes manifests for deploying the Nginx SSL proxy, which serves as the frontend gateway for the application.

## Component Description

The Nginx SSL proxy handles:
- TLS/SSL termination
- Request routing to backend services
- Static content serving
- Basic request filtering and security
- Load balancing

## Configuration

The Nginx configuration is stored in ConfigMaps:

- `nginx-config`: Contains the main nginx.conf configuration
- `lua-scripts`: Contains Lua scripts for advanced functionality

## Resource Management

- CPU Request: 100m (0.1 cores)
- CPU Limit: 500m (0.5 cores)
- Memory Request: 128Mi
- Memory Limit: 256Mi

## Health Checks

- **Readiness Probe**: HTTP check on `/health` endpoint with initial delay of 5 seconds
- **Liveness Probe**: HTTP check on `/health` endpoint with initial delay of 15 seconds

## SSL/TLS Configuration

SSL certificates are stored in a persistent volume:
```
/etc/nginx/ssl
```

The persistent volume claim `ssl-data` ensures certificates are preserved across pod restarts.

## Load Balancing

The service is configured with:
- Type: LoadBalancer (exposing ports 80 and 443)
- HTTP to HTTPS redirection
- Health check endpoints

## Ingress Routing

The Nginx proxy handles routing to various backend services:

| Path | Service |
|------|---------|
| `/api/tenants/*` | tenant-service |
| `/api/auth/*` | tenant-service |
| `/` | Static content |

## Deployment Configuration

The proxy is deployed with the following settings:
- Single replica in development (configurable in overlays)
- Multiple replicas in production for high availability
- Resource limits to prevent resource contention
- Health checks for automatic recovery

## Monitoring and Logging

- Access logs sent to stdout for collection by cluster logging
- Error logs for troubleshooting
- Metrics endpoint for Prometheus integration

## Security Considerations

- TLS configuration with strong cipher suites
- HTTP headers for security (HSTS, X-Frame-Options, etc.)
- Rate limiting for API endpoints
- Request filtering for basic protection

## Customization

To modify Nginx configuration:

1. Edit the ConfigMap in `configmap.yaml`
2. Apply changes:
   ```bash
   kubectl apply -f k8s/nginx/base/configmap.yaml
   ```

3. Force a rollout to apply changes:
   ```bash
   kubectl rollout restart deployment/nginx-ssl-proxy -n tenant-service-dev
   ``` 