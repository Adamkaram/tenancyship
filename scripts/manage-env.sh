#!/bin/bash

# Check if environment argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <environment> [action]"
    echo "Environment: dev or prod"
    echo "Action: apply (default), plan, or destroy"
    exit 1
fi

ENV=$1
ACTION=${2:-apply}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Validate environment
if [ "$ENV" != "dev" ] && [ "$ENV" != "prod" ]; then
    echo "Invalid environment. Use 'dev' or 'prod'"
    exit 1
fi

# Validate action
if [ "$ACTION" != "apply" ] && [ "$ACTION" != "plan" ] && [ "$ACTION" != "destroy" ]; then
    echo "Invalid action. Use 'apply', 'plan', or 'destroy'"
    exit 1
fi

# Change to terraform directory
cd "$PROJECT_ROOT/terraform" || exit 1

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Run Terraform
if [ "$ACTION" = "destroy" ]; then
    terraform destroy -var-file="secrets/${ENV}.tfvars"
else
    terraform ${ACTION} -var-file="secrets/${ENV}.tfvars"
fi

# If apply was successful and we're using Kubernetes, apply k8s configs
if [ "$ACTION" = "apply" ] && [ $? -eq 0 ]; then
    echo "Applying Kubernetes configurations..."
    kubectl apply -f "$PROJECT_ROOT/k8s/namespace.yaml"
    kubectl apply -f "$PROJECT_ROOT/k8s/deployment.yaml"
    kubectl apply -f "$PROJECT_ROOT/k8s/service.yaml"
fi 