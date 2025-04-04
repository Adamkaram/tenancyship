#!/bin/bash

# Tenant Service Management Script
# This script provides a unified interface for managing the tenant service project.
# It supports environment setup, deployment, and infrastructure management.

set -e  # Exit immediately if a command exits with a non-zero status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Common validation function
function validate_env {
    local ENV=$1
    if [ "$ENV" != "dev" ] && [ "$ENV" != "prod" ]; then
        echo "Invalid environment. Use 'dev' or 'prod'"
        exit 1
    fi
}

# Get namespace from environment
function get_namespace {
    local ENV=$1
    local VARS_FILE="$PROJECT_ROOT/terraform/secrets/${ENV}.tfvars"
    grep 'k8s_namespace' "$VARS_FILE" | cut -d '=' -f2 | tr -d ' "'
}

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
    echo "  ssl-status <env>        - Check SSL certificates status"
    echo "    <env>: dev or prod"
    echo ""
    echo "Examples:"
    echo "  $0 deploy dev           - Deploy to development environment"
    echo "  $0 deploy prod destroy  - Destroy production infrastructure"
    echo "  $0 install              - Install required tools"
    echo "  $0 status dev           - Check status of development deployment"
    echo "  $0 ssl-status prod      - Check SSL certificates in production"
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
    local ENV=$1
    local ACTION=${2:-apply}
    
    validate_env "$ENV"

    if [ "$ACTION" != "apply" ] && [ "$ACTION" != "plan" ] && [ "$ACTION" != "destroy" ]; then
        echo "Invalid action. Use 'apply', 'plan', or destroy"
        exit 1
    fi

    local VARS_FILE="$PROJECT_ROOT/terraform/secrets/${ENV}.tfvars"
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
        terraform apply -var-file="secrets/${ENV}.tfvars" && apply_k8s_configs "$ENV"
    fi
}

# Apply Kubernetes configurations
function apply_k8s_configs {
    local ENV=$1
    local NAMESPACE=$(get_namespace "$ENV")

    echo "Applying Kubernetes configurations for namespace: $NAMESPACE"
    
    # Create necessary directories if they don't exist
    mkdir -p "$PROJECT_ROOT/nginx/lua"
    
    # Create Nginx and Lua configurations if they don't exist
    if [ ! -f "$PROJECT_ROOT/nginx/nginx.conf" ]; then
        echo "Creating Nginx configuration..."
        cat > "$PROJECT_ROOT/nginx/nginx.conf" << 'EOF'
# Paste the nginx.conf content here (from the previous response)
EOF
    fi

    if [ ! -f "$PROJECT_ROOT/nginx/lua/ssl_automation.lua" ]; then
        echo "Creating SSL automation Lua script..."
        cat > "$PROJECT_ROOT/nginx/lua/ssl_automation.lua" << 'EOF'
# Paste the ssl_automation.lua content here (from the previous response)
EOF
    fi

    if [ ! -f "$PROJECT_ROOT/nginx/lua/tenant_resolver.lua" ]; then
        echo "Creating tenant resolver Lua script..."
        cat > "$PROJECT_ROOT/nginx/lua/tenant_resolver.lua" << 'EOF'
# Paste the tenant_resolver.lua content here (from the previous response)
EOF
    fi

    # Apply base Kubernetes configurations
    echo "Applying base Kubernetes configurations..."
    kubectl apply -f "$PROJECT_ROOT/k8s/namespace.yaml"
    
    # Create ConfigMaps for Nginx and Lua scripts
    echo "Creating ConfigMaps for Nginx and Lua scripts..."
    kubectl create configmap nginx-config \
        --from-file=nginx.conf="$PROJECT_ROOT/nginx/nginx.conf" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl create configmap lua-scripts \
        --from-file="$PROJECT_ROOT/nginx/lua/" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Apply persistent volume claims
    echo "Applying persistent volume claims..."
    kubectl apply -f "$PROJECT_ROOT/k8s/persistent-volumes.yaml"

    # Apply deployments
    echo "Applying deployments..."
    # Replace namespace placeholder in deployment files
    for file in "$PROJECT_ROOT"/k8s/*deployment.yaml; do
        sed "s/\${k8s_namespace}/$NAMESPACE/g" "$file" | kubectl apply -f -
    done

    # Apply services
    echo "Applying services..."
    for file in "$PROJECT_ROOT"/k8s/*service.yaml; do
        sed "s/\${k8s_namespace}/$NAMESPACE/g" "$file" | kubectl apply -f -
    done

    # Wait for deployments to be ready
    echo "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/tenant-service -n "$NAMESPACE"
    kubectl wait --for=condition=available --timeout=300s deployment/nginx-ssl-proxy -n "$NAMESPACE"
    kubectl wait --for=condition=available --timeout=300s deployment/redis -n "$NAMESPACE"

    # Show deployment status
    echo -e "\nDeployment Status:"
    kubectl get pods -n "$NAMESPACE"
    echo -e "\nServices:"
    kubectl get services -n "$NAMESPACE"
}

# Set up project for an environment
function setup_environment {
    local ENV=$1
    validate_env "$ENV"
    
    echo "Setting up $ENV environment..."
    
    # Create necessary directories if they don't exist
    mkdir -p "$PROJECT_ROOT/terraform/secrets"
    mkdir -p "$PROJECT_ROOT/k8s"
    mkdir -p "$PROJECT_ROOT/nginx/lua"
    
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
    local ENV=$1
    validate_env "$ENV"
    
    local NAMESPACE=$(get_namespace "$ENV")
    echo "Status for $ENV environment (namespace: $NAMESPACE):"
    kubectl get pods,services,deployments -n "$NAMESPACE"
}

# View logs
function view_logs {
    local ENV=$1
    validate_env "$ENV"
    
    local NAMESPACE=$(get_namespace "$ENV")
    local POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=tenant-service -o jsonpath="{.items[0].metadata.name}")
    
    if [ -z "$POD_NAME" ]; then
        echo "No tenant-service pods found in namespace $NAMESPACE"
        exit 1
    fi
    
    echo "Viewing logs for pod $POD_NAME in namespace $NAMESPACE..."
    kubectl logs -f "$POD_NAME" -n "$NAMESPACE"
}

# Check SSL status
function check_ssl_status {
    local ENV=$1
    validate_env "$ENV"
    
    local NAMESPACE=$(get_namespace "$ENV")
    
    echo "SSL Status for $ENV environment (namespace: $NAMESPACE):"
    echo -e "\nNginx Pods:"
    kubectl get pods -n "$NAMESPACE" -l app=nginx-ssl-proxy
    
    echo -e "\nSSL Certificates:"
    kubectl exec -n "$NAMESPACE" -l app=nginx-ssl-proxy -c nginx -- ls -l /etc/nginx/ssl/ 2>/dev/null || echo "No certificates found"
    
    echo -e "\nSSL-related logs:"
    kubectl logs -n "$NAMESPACE" -l app=nginx-ssl-proxy -c nginx --tail=20 | grep -i "ssl\|cert\|domain" || echo "No SSL-related logs found"
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
    ssl-status)
        if [ $# -lt 1 ]; then
            echo "Error: Missing environment parameter"
            show_help
        fi
        check_ssl_status "$1"
        ;;
    *)
        echo "Unknown command: $COMMAND"
        show_help
        ;;
esac 