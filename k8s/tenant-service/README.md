# Tenant Service in Kubernetes

This directory contains the Kubernetes manifests for deploying the Tenant Service, which is the core backend component of the application.

## Service Description

The Tenant Service is responsible for:
- Managing tenant accounts and data
- Processing API requests from clients
- Interacting with the database layer
- Authentication and authorization

## Configuration

The service is configured through environment variables managed by a ConfigMap:

- `ENVIRONMENT_TYPE`: The environment type (development, staging, production)
- `LOG_LEVEL`: Log verbosity (debug, info, warning, error)
- `API_VERSION`: API version being served

## Resource Management

- CPU Request: 100m (0.1 cores)
- CPU Limit: 500m (0.5 cores)
- Memory Request: 128Mi
- Memory Limit: 512Mi

## Health Checks

- **Readiness Probe**: HTTP check on `/health` endpoint with initial delay of 5 seconds
- **Liveness Probe**: HTTP check on `/health` endpoint with initial delay of 15 seconds

## Secrets Management

The service uses a Kubernetes Secret named `surrealdb-creds` to store database credentials, mounted at:
```
/mnt/secrets/surrealdb-creds
```

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `/health` | Health check endpoint |
| `/api/v1/tenants` | Tenant management endpoints |
| `/api/v1/auth` | Authentication endpoints |

## Deployment Configuration

The service is deployed with the following settings:
- Single replica in development (configurable in overlays)
- Multiple replicas in production for high availability
- Resource limits to prevent resource contention
- Health checks for automatic recovery

## Local Development

For local development:

1. Build the tenant-service container:
   ```bash
   cd tenant-service
   docker build -t tenant-service:v1.0.0 .
   ```

2. Deploy to a local Kubernetes cluster:
   ```bash
   kubectl apply -k k8s/tenant-service/base
   ```

Or use the main deployment script:
```bash
./scripts/deploy-k8s.sh dev
```

## Troubleshooting

Common issues:

1. **Database connection failures**:
   - Check if the surrealdb-creds secret is properly configured
   - Verify network connectivity to the database
   - Check for correct environment variables

2. **Resource constraints**:
   - Monitor CPU and memory usage
   - Adjust resource limits if necessary

3. **API errors**:
   - Check logs using `kubectl logs deployment/tenant-service`
   - Verify configuration settings 