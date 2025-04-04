#!/bin/bash

# Initialize and apply Terraform
cd terraform
terraform init
terraform apply -auto-approve

# Apply Kubernetes configurations
cd ../k8s
kubectl apply -f namespace.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

echo "Deployment complete!" 