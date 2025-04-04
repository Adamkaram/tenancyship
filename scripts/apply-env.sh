#!/bin/bash

# Check if environment argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <environment>"
    echo "Available environments: dev, prod"
    exit 1
fi

ENV=$1
VARS_FILE="terraform/secrets/${ENV}.tfvars"

# Check if vars file exists
if [ ! -f "$VARS_FILE" ]; then
    echo "Error: Variables file $VARS_FILE not found"
    exit 1
fi

# Initialize Terraform
cd terraform
terraform init

# Plan and apply with environment variables
terraform plan -var-file="secrets/${ENV}.tfvars" -out=tfplan
terraform apply tfplan

# Apply Kubernetes configurations
cd ../k8s
kubectl apply -f namespace.yaml
kubectl apply -f deployment.yaml -n $(terraform output -raw k8s_namespace)
kubectl apply -f service.yaml -n $(terraform output -raw k8s_namespace)

echo "Deployment to ${ENV} environment complete!" 