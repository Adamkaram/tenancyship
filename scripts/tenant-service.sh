#!/bin/bash

# Tenant Service Management Script
# This script provides a unified interface for managing the tenant service project.
# It supports environment setup, deployment, and infrastructure management.

set -e  # Exit immediately if a command exits with a non-zero status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Display help message
function show_help {
    echo "Tenant Service Management Tool"
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  deploy <env> [action]   - Manage infrastructure deployment"
    echo "    <env>: dev or prod"
    echo "    [action]: apply (default), plan, or destroy"
    echo ""
    echo "  install                 - Install required tools (requires sudo)"
    echo ""
    echo "  setup <env>             - Set up project structure for an environment"
    echo "    <env>: dev or prod"
    echo ""
    echo "  status <env>            - Check deployment status"
    echo "    <env>: dev or prod"
    echo ""
    echo "  logs <env>              - View tenant service logs"
    echo "    <env>: dev or prod"
    echo ""
    echo "Examples:"
    echo "  $0 deploy dev           - Deploy to development environment"
    echo "  $0 deploy prod destroy  - Destroy production infrastructure"
    echo "  $0 install              - Install required tools"
    echo "  $0 status dev           - Check status of development deployment"
    exit 1
}

# Install required tools
function install_tools {
    echo "Installing required tools..."

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        echo "Please run with sudo: sudo $0 install"
        exit 1
    fi

    # Update package list
    apt-get update

    # Install prerequisites
    apt-get install -y \
        curl \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common

    # Install Terraform
    curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
    apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
    apt-get update && apt-get install -y terraform

    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl

    # Install Vault
    curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
    apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
    apt-get update && apt-get install -y vault

    echo "Installation complete!"
    echo "Versions installed:"
    terraform --version
    kubectl version --client
    vault --version
}

# Deploy/manage infrastructure
function deploy_infrastructure {
    ENV=$1
    ACTION=${2:-apply}

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

    VARS_FILE="$PROJECT_ROOT/terraform/secrets/${ENV}.tfvars"
    
    # Check if vars file exists
    if [ ! -f "$VARS_FILE" ]; then
        echo "Error: Variables file $VARS_FILE not found."
        echo "Please create it based on the template or run: $0 setup $ENV"
        exit 1
    fi

    # Change to terraform directory
    echo "Changing to terraform directory..."
    cd "$PROJECT_ROOT/terraform"

    # Initialize Terraform if needed
    if [ ! -d ".terraform" ]; then
        echo "Initializing Terraform..."
        terraform init
    fi

    # Run Terraform
    echo "Running Terraform $ACTION for $ENV environment..."
    if [ "$ACTION" = "destroy" ]; then
        terraform destroy -var-file="secrets/${ENV}.tfvars"
    elif [ "$ACTION" = "plan" ]; then
        terraform plan -var-file="secrets/${ENV}.tfvars" -out=tfplan
        echo "Plan saved to tfplan. To apply, run: cd terraform && terraform apply tfplan"
    else
        terraform apply -var-file="secrets/${ENV}.tfvars"
    fi

    # If apply was successful, apply k8s configs
    if [ "$ACTION" = "apply" ] && [ $? -eq 0 ]; then
        echo "Applying Kubernetes configurations..."
        # Get namespace from the variables file
        NAMESPACE=$(grep 'k8s_namespace' "$VARS_FILE" | cut -d '=' -f2 | tr -d ' "')
        
        kubectl apply -f "$PROJECT_ROOT/k8s/namespace.yaml"
        
        # Apply deployment and service with the correct namespace
        sed "s/\${k8s_namespace}/$NAMESPACE/g" "$PROJECT_ROOT/k8s/deployment.yaml" | kubectl apply -f -
        sed "s/\${k8s_namespace}/$NAMESPACE/g" "$PROJECT_ROOT/k8s/service.yaml" | kubectl apply -f -
        
        echo "Deployment to $ENV environment complete!"
    fi
}

# Set up project for an environment
function setup_environment {
    ENV=$1
    
    # Validate environment
    if [ "$ENV" != "dev" ] && [ "$ENV" != "prod" ]; then
        echo "Invalid environment. Use 'dev' or 'prod'"
        exit 1
    fi
    
    echo "Setting up $ENV environment..."
    
    # Create necessary directories if they don't exist
    mkdir -p "$PROJECT_ROOT/terraform/secrets"
    mkdir -p "$PROJECT_ROOT/k8s"
    
    # Use template.tfvars to create the environment file if it doesn't exist
    TEMPLATE_FILE="$PROJECT_ROOT/terraform/secrets/template.tfvars"
    ENV_FILE="$PROJECT_ROOT/terraform/secrets/${ENV}.tfvars"
    
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f "$TEMPLATE_FILE" ]; then
            cp "$TEMPLATE_FILE" "$ENV_FILE"
            echo "Created $ENV_FILE from template."
            echo "Please edit this file to set your environment-specific values."
        else
            echo "Template file not found. Creating a basic environment file..."
            cat > "$ENV_FILE" << EOF
# $ENV environment variables
vault_addr = "http://localhost:8200"
vault_token = "your-token-here"

surrealdb_url = "wss://your-surrealdb-instance"
surrealdb_user = "root"
surrealdb_password = "your-password"
surrealdb_ns = "test"
surrealdb_db = "test"

k8s_namespace = "tenant-service-$ENV"
EOF
            echo "Created basic $ENV_FILE."
            echo "Please edit this file to set your environment-specific values."
        fi
    else
        echo "$ENV_FILE already exists."
    fi
    
    echo "Environment setup complete!"
}

# Check deployment status
function check_status {
    ENV=$1
    
    # Validate environment
    if [ "$ENV" != "dev" ] && [ "$ENV" != "prod" ]; then
        echo "Invalid environment. Use 'dev' or 'prod'"
        exit 1
    fi
    
    # Get namespace from the variables file
    VARS_FILE="$PROJECT_ROOT/terraform/secrets/${ENV}.tfvars"
    if [ ! -f "$VARS_FILE" ]; then
        echo "Error: Variables file $VARS_FILE not found."
        exit 1
    fi
    
    NAMESPACE=$(grep 'k8s_namespace' "$VARS_FILE" | cut -d '=' -f2 | tr -d ' "')
    
    echo "Checking status for $ENV environment (namespace: $NAMESPACE)..."
    echo ""
    echo "=== Pods ==="
    kubectl get pods -n "$NAMESPACE"
    echo ""
    echo "=== Services ==="
    kubectl get services -n "$NAMESPACE"
    echo ""
    echo "=== Deployments ==="
    kubectl get deployments -n "$NAMESPACE"
    echo ""
    echo "=== Secrets ==="
    kubectl get secrets -n "$NAMESPACE"
}

# View logs
function view_logs {
    ENV=$1
    
    # Validate environment
    if [ "$ENV" != "dev" ] && [ "$ENV" != "prod" ]; then
        echo "Invalid environment. Use 'dev' or 'prod'"
        exit 1
    fi
    
    # Get namespace from the variables file
    VARS_FILE="$PROJECT_ROOT/terraform/secrets/${ENV}.tfvars"
    if [ ! -f "$VARS_FILE" ]; then
        echo "Error: Variables file $VARS_FILE not found."
        exit 1
    fi
    
    NAMESPACE=$(grep 'k8s_namespace' "$VARS_FILE" | cut -d '=' -f2 | tr -d ' "')
    
    # Get the pod name
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=tenant-service -o jsonpath="{.items[0].metadata.name}")
    
    if [ -z "$POD_NAME" ]; then
        echo "No tenant-service pods found in namespace $NAMESPACE"
        exit 1
    fi
    
    echo "Viewing logs for pod $POD_NAME in namespace $NAMESPACE..."
    kubectl logs -f "$POD_NAME" -n "$NAMESPACE"
}

# Main command processing
if [ $# -lt 1 ]; then
    show_help
fi

COMMAND=$1
shift

case $COMMAND in
    deploy)
        if [ $# -lt 1 ]; then
            echo "Error: Missing environment parameter"
            show_help
        fi
        deploy_infrastructure "$@"
        ;;
    install)
        install_tools
        ;;
    setup)
        if [ $# -lt 1 ]; then
            echo "Error: Missing environment parameter"
            show_help
        fi
        setup_environment "$1"
        ;;
    status)
        if [ $# -lt 1 ]; then
            echo "Error: Missing environment parameter"
            show_help
        fi
        check_status "$1"
        ;;
    logs)
        if [ $# -lt 1 ]; then
            echo "Error: Missing environment parameter"
            show_help
        fi
        view_logs "$1"
        ;;
    *)
        echo "Unknown command: $COMMAND"
        show_help
        ;;
esac 