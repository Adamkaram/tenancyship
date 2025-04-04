#!/bin/bash

# Exit on error
set -e

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if kustomize is installed
if ! command -v kustomize &> /dev/null; then
    echo "kustomize is not installed. Installing kustomize..."
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
fi

# Function to deploy to an environment
deploy_to_env() {
    local env=$1
    echo "Deploying to $env environment..."
    
    # Build the kustomization
    kustomize build k8s/overlays/$env | kubectl apply -f -
    
    # Wait for deployments to be ready
    echo "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available deployment/tenant-service -n tenant-service-$env --timeout=300s
    kubectl wait --for=condition=available deployment/nginx-ssl-proxy -n tenant-service-$env --timeout=300s
    kubectl wait --for=condition=available deployment/redis -n tenant-service-$env --timeout=300s
    
    echo "Deployment to $env environment completed successfully!"
}

# Main script
case "$1" in
    "dev")
        deploy_to_env "dev"
        ;;
    "prod")
        deploy_to_env "prod"
        ;;
    *)
        echo "Usage: $0 {dev|prod}"
        exit 1
        ;;
esac 