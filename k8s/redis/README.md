# Redis in Kubernetes

This directory contains the Kubernetes manifests for deploying Redis as a caching layer for the tenant service.

## Configuration

Redis is configured with the following optimizations:

1. **Memory Management**
   - `maxmemory` set to 256MB to prevent OOM issues
   - `maxmemory-policy` set to allkeys-lru to evict least recently used keys when memory is full

2. **Persistence**
   - `appendonly` enabled for better durability
   - RDB snapshots configured to save:
     - Every 15 minutes if at least 1 change occurred
     - Every 5 minutes if at least 10 changes occurred
     - Every 60 seconds if at least 10000 changes occurred

3. **Connection Handling**
   - `tcp-keepalive` set to 60 seconds to detect stale connections

4. **Logging**
   - `loglevel` set to notice for important events

## Resource Management

- CPU Request: 100m (0.1 cores)
- CPU Limit: 500m (0.5 cores)
- Memory Request: 128Mi
- Memory Limit: 256Mi

## Health Checks

- **Readiness Probe**: TCP socket check on port 6379 with initial delay of 5 seconds
- **Liveness Probe**: TCP socket check on port 6379 with initial delay of 15 seconds

## Data Persistence

Redis uses a PersistentVolumeClaim named `redis-data` with 1Gi storage to ensure data is preserved across pod restarts.

## Custom Configuration

To modify Redis configuration, edit the ConfigMap in `configmap.yaml`. After updating, apply changes using:

```bash
kubectl apply -f k8s/redis/base/configmap.yaml
```

Alternatively, apply changes through Kustomize:

```bash
kubectl apply -k k8s/redis/base
```

## Scaling

Redis is deployed as a single instance by default. For a production-ready, highly available Redis setup, consider using Redis Sentinel or Redis Cluster, which would require additional configuration beyond the scope of this basic setup. 