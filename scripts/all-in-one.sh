#!/bin/bash

# Exit on error
set -e

# Define colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Define paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Handle case when script is called via symlink
if [[ "$(basename "${BASH_SOURCE[0]}")" == "manage" ]]; then
    # When called as ./manage, we're in the project root already
    PROJECT_ROOT="$(pwd)"
else
    # When called directly from scripts/ directory
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# Helper functions
print_header() {
    echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

print_success() {
    echo -e "\n${GREEN}✓ $1${NC}\n"
}

print_error() {
    echo -e "\n${RED}✗ $1${NC}\n"
}

print_warning() {
    echo -e "\n${YELLOW}! $1${NC}\n"
}

# Common validation function
validate_env() {
    local ENV=$1
    if [ "$ENV" != "dev" ] && [ "$ENV" != "prod" ]; then
        print_error "Invalid environment. Use 'dev' or 'prod'"
        return 1
    fi
    return 0
}

# Get namespace from environment
get_namespace() {
    local ENV=$1
    if [ -f "$PROJECT_ROOT/terraform/secrets/${ENV}.tfvars" ]; then
        grep 'k8s_namespace' "$PROJECT_ROOT/terraform/secrets/${ENV}.tfvars" | cut -d '=' -f2 | tr -d ' "'
    else
        echo "tenant-service-$ENV"
    fi
}

# PART 1: KUBERNETES DEPLOYMENT FUNCTIONS
# --------------------------------------

# Check if kubectl is installed
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
}

# Check if kustomize is installed
check_kustomize() {
    if ! command -v kustomize &> /dev/null; then
        print_warning "kustomize is not installed. Installing kustomize..."
        curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
        sudo mv kustomize /usr/local/bin/
    fi
}

# Function to deploy to an environment using kustomize
deploy_kustomize() {
    local env=$1
    print_header "Deploying to $env environment using Kustomize"
    
    check_kubectl
    check_kustomize
    
    print_header "Building and applying Kubernetes manifests"
    kustomize build "$PROJECT_ROOT/k8s/overlays/$env" | kubectl apply -f -
    
    print_header "Waiting for deployments to be ready"
    kubectl wait --for=condition=available deployment/tenant-service -n tenant-service-$env --timeout=300s
    kubectl wait --for=condition=available deployment/nginx-ssl-proxy -n tenant-service-$env --timeout=300s
    kubectl wait --for=condition=available deployment/redis -n tenant-service-$env --timeout=300s
    
    print_success "Deployment to $env environment completed successfully!"
}

# Function to apply Kubernetes configurations directly
apply_k8s_configs() {
    local ENV=$1
    local NAMESPACE=$(get_namespace "$ENV")

    print_header "Applying Kubernetes configurations for namespace: $NAMESPACE"
    
    check_kubectl
    
    # Create necessary directories if they don't exist
    mkdir -p "$PROJECT_ROOT/nginx/lua"
    
    # Create Nginx and Lua configurations if they don't exist
    if [ ! -f "$PROJECT_ROOT/nginx/nginx.conf" ]; then
        print_warning "nginx.conf not found, creating default configuration..."
        cat > "$PROJECT_ROOT/nginx/nginx.conf" << 'EOF'
# Default nginx.conf
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    # Lua settings
    lua_package_path "/etc/nginx/lua/?.lua;;";
    
    server {
        listen 80;
        server_name _;
        
        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }
        
        location / {
            proxy_pass http://tenant-service;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF
    fi

    # Apply base Kubernetes configurations
    print_header "Applying base Kubernetes configurations..."
    kubectl apply -f "$PROJECT_ROOT/k8s/base/namespace.yaml"
    
    # Create ConfigMaps for Nginx and Lua scripts
    print_header "Creating ConfigMaps for Nginx and Lua scripts..."
    kubectl create configmap nginx-config \
        --from-file=nginx.conf="$PROJECT_ROOT/nginx/nginx.conf" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    if [ -d "$PROJECT_ROOT/nginx/lua/" ]; then
        kubectl create configmap lua-scripts \
            --from-file="$PROJECT_ROOT/nginx/lua/" \
            -n "$NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -
    fi

    # Apply persistent volume claims
    print_header "Applying persistent volume claims..."
    kubectl apply -f "$PROJECT_ROOT/k8s/base/persistent-volumes.yaml"

    # Apply component manifests
    print_header "Applying deployments and services..."
    
    # Apply tenant-service manifests
    kubectl apply -f "$PROJECT_ROOT/k8s/tenant-service/base/deployment.yaml" -n "$NAMESPACE"
    kubectl apply -f "$PROJECT_ROOT/k8s/tenant-service/base/service.yaml" -n "$NAMESPACE"
    kubectl apply -f "$PROJECT_ROOT/k8s/tenant-service/base/configmap.yaml" -n "$NAMESPACE"
    
    # Apply nginx manifests
    kubectl apply -f "$PROJECT_ROOT/k8s/nginx/base/deployment.yaml" -n "$NAMESPACE"
    kubectl apply -f "$PROJECT_ROOT/k8s/nginx/base/service.yaml" -n "$NAMESPACE"
    
    # Apply redis manifests
    kubectl apply -f "$PROJECT_ROOT/k8s/redis/base/deployment.yaml" -n "$NAMESPACE"
    kubectl apply -f "$PROJECT_ROOT/k8s/redis/base/service.yaml" -n "$NAMESPACE"
    kubectl apply -f "$PROJECT_ROOT/k8s/redis/base/configmap.yaml" -n "$NAMESPACE"
    kubectl apply -f "$PROJECT_ROOT/k8s/redis/base/pvc.yaml" -n "$NAMESPACE"
    
    print_success "Kubernetes configurations applied successfully!"
}

# PART 2: TERRAFORM AND INFRASTRUCTURE FUNCTIONS
# --------------------------------------

# Check if Terraform is installed
check_terraform() {
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi
}

# Deploy/manage infrastructure with Terraform
deploy_infrastructure() {
    local ENV=$1
    local ACTION=${2:-apply}
    
    if ! validate_env "$ENV"; then
        return 1
    fi

    if [ "$ACTION" != "apply" ] && [ "$ACTION" != "plan" ] && [ "$ACTION" != "destroy" ]; then
        print_error "Invalid action. Use 'apply', 'plan', or destroy"
        return 1
    fi

    check_terraform

    local VARS_FILE="$PROJECT_ROOT/terraform/secrets/${ENV}.tfvars"
    if [ ! -f "$VARS_FILE" ]; then
        print_error "Error: Variables file $VARS_FILE not found."
        print_warning "Please create it based on the template or run setup function first."
        return 1
    fi

    # Change to terraform directory
    print_header "Changing to terraform directory..."
    cd "$PROJECT_ROOT/terraform"

    # Initialize Terraform if needed
    if [ ! -d ".terraform" ]; then
        print_header "Initializing Terraform..."
        terraform init
    fi

    # Run Terraform
    print_header "Running Terraform $ACTION for $ENV environment..."
    if [ "$ACTION" = "destroy" ]; then
        terraform destroy -var-file="secrets/${ENV}.tfvars"
    elif [ "$ACTION" = "plan" ]; then
        terraform plan -var-file="secrets/${ENV}.tfvars" -out=tfplan
        print_success "Plan saved to tfplan. To apply, run: cd terraform && terraform apply tfplan"
    else
        terraform apply -var-file="secrets/${ENV}.tfvars" && apply_k8s_configs "$ENV"
        print_success "Infrastructure deployed successfully for $ENV environment!"
    fi
}

# Setup environment
setup_environment() {
    local ENV=$1
    
    if ! validate_env "$ENV"; then
        return 1
    fi

    print_header "Setting up $ENV environment..."
    
    # Create terraform secrets directory if it doesn't exist
    mkdir -p "$PROJECT_ROOT/terraform/secrets"
    
    # Create template tfvars file if it doesn't exist
    local VARS_FILE="$PROJECT_ROOT/terraform/secrets/${ENV}.tfvars"
    if [ ! -f "$VARS_FILE" ]; then
        print_header "Creating template variables file for $ENV environment..."
        cat > "$VARS_FILE" << EOF
# Environment
environment = "${ENV}"
k8s_namespace = "tenant-service-${ENV}"

# Infrastructure settings
region = "us-west-2"
instance_type = "t3.micro"

# Application settings
app_replicas = 1
enable_ssl = true
domain_name = "example.com"
EOF
        print_success "Template variables file created at $VARS_FILE"
        print_warning "Please customize the variables in $VARS_FILE before deploying."
    else
        print_warning "Variables file $VARS_FILE already exists. Skipping."
    fi
    
    print_success "Environment setup completed for $ENV!"
}

# Install required tools
install_tools() {
    print_header "Installing required tools..."

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        print_error "Please run with sudo: sudo $0 install"
        return 1
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

    # Install Kustomize
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    install -o root -g root -m 0755 kustomize /usr/local/bin/kustomize
    rm kustomize

    print_success "Installation complete!"
    print_header "Versions installed:"
    terraform --version
    kubectl version --client
    kustomize version
}

# Check SSL certificates status
check_ssl_status() {
    local ENV=$1
    
    if ! validate_env "$ENV"; then
        return 1
    fi
    
    check_kubectl
    
    local NAMESPACE=$(get_namespace "$ENV")
    
    print_header "Checking SSL certificates status in $ENV environment..."
    
    # Get pods running nginx
    local NGINX_POD=$(kubectl get pods -n "$NAMESPACE" -l app=nginx-ssl-proxy -o jsonpath="{.items[0].metadata.name}")
    
    if [ -z "$NGINX_POD" ]; then
        print_error "No nginx pod found in namespace $NAMESPACE"
        return 1
    fi
    
    # Check SSL certificates
    kubectl exec -it "$NGINX_POD" -n "$NAMESPACE" -- ls -la /etc/nginx/ssl/
    
    print_success "SSL certificate check completed!"
}

# PART 3: LOCAL DEVELOPMENT FUNCTIONS
# --------------------------------------

# Function to run the local app
run_local_app() {
    print_header "Running the local application"
    cd "$PROJECT_ROOT"
    
    echo "Choose how to run the application:"
    echo "1) Run with Go directly"
    echo "2) Run with podman-compose (recommended)"
    read -p "Enter your choice (1 or 2): " choice

    case $choice in
        1)
            print_header "Running with Go directly..."
            go run main.go
            ;;
        2)
            print_header "Running with podman-compose..."
            
            # Check if virtual environment exists
            if [ ! -d ".venv" ]; then
                print_header "Virtual environment not found, creating one..."
                # Install uv if not already installed
                if ! command -v uv &> /dev/null; then
                    print_header "Installing/checking uv package manager..."
                    curl -LsSf https://astral.sh/uv/install.sh | sh
                fi
                
                # Create virtual environment
                uv venv
            fi
            
            # Activate the virtual environment
            print_header "Activating virtual environment..."
            source .venv/bin/activate
            
            # Check if podman-compose is installed
            if ! command -v podman-compose &> /dev/null; then
                print_header "Installing podman-compose..."
                uv pip install podman-compose
            fi
            
            # Run podman-compose
            podman-compose up --build
            
            # Deactivate the virtual environment
            deactivate
            ;;
        *)
            print_error "Invalid choice. Please enter 1 or 2."
            return 1
            ;;
    esac
}

# Function to run the Rust tenant service
run_rust_service() {
    print_header "Running the Rust tenant service"
    cd "$PROJECT_ROOT"
    
    # Check if Rust is installed
    if ! command -v rustc &> /dev/null; then
        print_warning "Rust is not installed. Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        source $HOME/.cargo/env
    fi

    # Navigate to tenant-service directory
    cd tenant-service

    # Run the service
    print_header "Running Rust tenant service..."
    cargo run
}

# Function to deploy locally using podman-compose
deploy_local() {
    print_header "Deploying locally using Podman containers"
    cd "$PROJECT_ROOT"
    
    # Check if docker-compose.yml or similar files exist
    if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ] && [ ! -f "$PROJECT_ROOT/compose.yaml" ] && [ ! -f "$PROJECT_ROOT/container-compose.yml" ]; then
        print_warning "No compose file found (docker-compose.yml, compose.yaml, or container-compose.yml)"
        read -p "Would you like to create a basic docker-compose.yml file? (y/n): " create_file
        
        if [ "$create_file" = "y" ]; then
            print_header "Creating a basic docker-compose.yml file..."
            cat > "$PROJECT_ROOT/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  main-app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      - TENANT_SERVICE_URL=http://tenant-service:8080
    depends_on:
      - tenant-service

  tenant-service:
    build:
      context: ./tenant-service
      dockerfile: Dockerfile
    ports:
      - "8081:8080"

networks:
  default:
    driver: bridge
EOF
            print_success "Created docker-compose.yml file"
        else
            print_error "Cannot continue without a compose file. Please create one manually."
            return 1
        fi
    fi
    
    # Install uv if not already installed
    print_header "Installing/checking uv package manager..."
    if ! command -v uv &> /dev/null; then
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

    # Create and activate a virtual environment
    print_header "Setting up virtual environment..."
    if [ ! -d ".venv" ]; then
        uv venv
    fi
    
    # Explicitly activate the virtual environment
    source .venv/bin/activate

    # Install podman-compose
    print_header "Installing podman-compose..."
    uv pip install podman-compose

    # Clean up existing containers and images
    print_header "Cleaning up existing containers and images..."
    podman-compose down --volumes || print_warning "No existing containers to clean up"
    podman system prune -f

    # Build and run with podman-compose
    print_header "Building and running with podman-compose..."
    podman-compose -f "$PROJECT_ROOT/docker-compose.yml" build --no-cache
    podman-compose -f "$PROJECT_ROOT/docker-compose.yml" up
    
    # Deactivate the virtual environment
    deactivate
}

# PART 4: KUBERNETES MANAGEMENT FUNCTIONS
# --------------------------------------

# Function to show Kubernetes resources
show_k8s_resources() {
    local env=$1
    
    if ! validate_env "$env"; then
        return 1
    fi
    
    print_header "Showing Kubernetes resources in $env environment"
    
    check_kubectl
    
    local NAMESPACE=$(get_namespace "$env")
    
    echo -e "${YELLOW}Namespaces:${NC}"
    kubectl get ns | grep "$NAMESPACE"
    
    echo -e "\n${YELLOW}Deployments:${NC}"
    kubectl get deployments -n "$NAMESPACE"
    
    echo -e "\n${YELLOW}Services:${NC}"
    kubectl get svc -n "$NAMESPACE"
    
    echo -e "\n${YELLOW}Pods:${NC}"
    kubectl get pods -n "$NAMESPACE"
    
    echo -e "\n${YELLOW}ConfigMaps:${NC}"
    kubectl get configmaps -n "$NAMESPACE"
    
    echo -e "\n${YELLOW}PersistentVolumeClaims:${NC}"
    kubectl get pvc -n "$NAMESPACE"
}

# Function to get pod logs
get_pod_logs() {
    local env=$1
    
    if ! validate_env "$env"; then
        return 1
    fi
    
    print_header "Getting pod logs in $env environment"
    
    check_kubectl
    
    local NAMESPACE=$(get_namespace "$env")
    
    echo -e "${YELLOW}Available pods:${NC}"
    kubectl get pods -n "$NAMESPACE"
    
    read -p "Enter pod name: " pod_name
    
    if [ -z "$pod_name" ]; then
        print_error "No pod name provided."
        return 1
    fi
    
    kubectl logs "$pod_name" -n "$NAMESPACE"
}

# Function to restart deployments
restart_deployments() {
    local env=$1
    
    if ! validate_env "$env"; then
        return 1
    fi
    
    print_header "Restarting deployments in $env environment"
    
    check_kubectl
    
    local NAMESPACE=$(get_namespace "$env")
    
    kubectl rollout restart deployment/tenant-service -n "$NAMESPACE"
    kubectl rollout restart deployment/nginx-ssl-proxy -n "$NAMESPACE"
    kubectl rollout restart deployment/redis -n "$NAMESPACE"
    
    print_success "Deployments restarted successfully!"
}

# Function to clean up resources
cleanup_resources() {
    local env=$1
    
    if ! validate_env "$env"; then
        return 1
    fi
    
    print_header "Cleaning up resources in $env environment"
    
    check_kubectl
    
    local NAMESPACE=$(get_namespace "$env")
    
    read -p "Are you sure you want to delete all resources in the $env environment? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        print_warning "Cleanup aborted."
        return 0
    fi
    
    print_header "Deleting Kubernetes resources"
    if [ -d "$PROJECT_ROOT/k8s/overlays/$env" ]; then
        kustomize build "$PROJECT_ROOT/k8s/overlays/$env" | kubectl delete -f -
    else
        kubectl delete namespace "$NAMESPACE"
    fi
    
    print_success "Cleanup completed successfully!"
}

# Function to open a shell in a pod
shell_into_pod() {
    local env=$1
    
    if ! validate_env "$env"; then
        return 1
    fi
    
    print_header "Opening a shell in a pod in $env environment"
    
    check_kubectl
    
    local NAMESPACE=$(get_namespace "$env")
    
    echo -e "${YELLOW}Available pods:${NC}"
    kubectl get pods -n "$NAMESPACE"
    
    read -p "Enter pod name: " pod_name
    
    if [ -z "$pod_name" ]; then
        print_error "No pod name provided."
        return 1
    fi
    
    kubectl exec -it "$pod_name" -n "$NAMESPACE" -- /bin/sh
}

# PART 5: MENU SYSTEM
# --------------------------------------

# Show help message
show_help() {
    echo "All-in-One Management Script"
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  menu                    - Show interactive menu (default)"
    echo ""
    echo "  deploy <env> [action]   - Manage infrastructure deployment"
    echo "    <env>: dev or prod"
    echo "    [action]: apply (default), plan, or destroy"
    echo ""
    echo "  kustomize <env>         - Deploy using Kustomize"
    echo "    <env>: dev or prod"
    echo ""
    echo "  install                 - Install required tools (requires sudo)"
    echo ""
    echo "  setup <env>             - Set up project structure for an environment"
    echo "    <env>: dev or prod"
    echo ""
    echo "  status <env>            - Check deployment status"
    echo "    <env>: dev or prod"
    echo ""
    echo "  logs <env>              - View logs from pods"
    echo "    <env>: dev or prod"
    echo ""
    echo "  ssl-status <env>        - Check SSL certificates status"
    echo "    <env>: dev or prod"
    echo ""
    echo "  shell <env>             - Open shell in a pod"
    echo "    <env>: dev or prod"
    echo ""
    echo "  restart <env>           - Restart deployments"
    echo "    <env>: dev or prod"
    echo ""
    echo "  cleanup <env>           - Clean up resources"
    echo "    <env>: dev or prod"
    echo ""
    echo "  run-local               - Run the local application (run.sh)"
    echo "  run-rust                - Run the Rust tenant service (run_rust.sh)"
    echo "  deploy-local            - Deploy locally using docker-compose (deploy.sh)"
    echo ""
    echo "Examples:"
    echo "  $0                      - Show interactive menu"
    echo "  $0 deploy dev           - Deploy to development environment"
    echo "  $0 kustomize prod       - Deploy to production using Kustomize"
    echo "  $0 status dev           - Check status of development deployment"
}

# Main menu
main_menu() {
    clear
    print_header "All-in-One Management Script"
    echo -e "1. ${GREEN}Development Environment${NC}"
    echo -e "2. ${YELLOW}Production Environment${NC}"
    echo -e "3. ${BLUE}Local Development${NC}"
    echo -e "4. ${BLUE}Tools & Setup${NC}"
    echo -e "5. ${RED}Exit${NC}"
    echo ""
    read -p "Enter your choice [1-5]: " main_choice
    
    case $main_choice in
        1)
            dev_env_menu
            ;;
        2)
            prod_env_menu
            ;;
        3)
            local_dev_menu
            ;;
        4)
            tools_menu
            ;;
        5)
            print_success "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid choice. Please try again."
            main_menu
            ;;
    esac
}

# Development environment menu
dev_env_menu() {
    clear
    print_header "Development Environment Management"
    echo "1. Deploy using Kustomize"
    echo "2. Deploy using Terraform + K8s"
    echo "3. Show Kubernetes resources"
    echo "4. Get pod logs"
    echo "5. Restart deployments"
    echo "6. Shell into a pod"
    echo "7. Check SSL certificates"
    echo "8. Clean up resources"
    echo "9. Back to main menu"
    echo ""
    read -p "Enter your choice [1-9]: " dev_choice
    
    case $dev_choice in
        1)
            deploy_kustomize "dev"
            read -p "Press enter to continue..."
            dev_env_menu
            ;;
        2)
            deploy_infrastructure "dev" "apply"
            read -p "Press enter to continue..."
            dev_env_menu
            ;;
        3)
            show_k8s_resources "dev"
            read -p "Press enter to continue..."
            dev_env_menu
            ;;
        4)
            get_pod_logs "dev"
            read -p "Press enter to continue..."
            dev_env_menu
            ;;
        5)
            restart_deployments "dev"
            read -p "Press enter to continue..."
            dev_env_menu
            ;;
        6)
            shell_into_pod "dev"
            dev_env_menu
            ;;
        7)
            check_ssl_status "dev"
            read -p "Press enter to continue..."
            dev_env_menu
            ;;
        8)
            cleanup_resources "dev"
            read -p "Press enter to continue..."
            dev_env_menu
            ;;
        9)
            main_menu
            ;;
        *)
            print_error "Invalid choice. Please try again."
            dev_env_menu
            ;;
    esac
}

# Production environment menu
prod_env_menu() {
    clear
    print_header "Production Environment Management"
    echo "1. Deploy using Kustomize"
    echo "2. Deploy using Terraform + K8s"
    echo "3. Show Kubernetes resources"
    echo "4. Get pod logs"
    echo "5. Restart deployments"
    echo "6. Shell into a pod"
    echo "7. Check SSL certificates"
    echo "8. Clean up resources"
    echo "9. Back to main menu"
    echo ""
    read -p "Enter your choice [1-9]: " prod_choice
    
    case $prod_choice in
        1)
            # Confirmation for production deployment
            read -p "Are you sure you want to deploy to production? (y/n): " confirm
            if [ "$confirm" = "y" ]; then
                deploy_kustomize "prod"
            else
                print_warning "Deployment to production aborted."
            fi
            read -p "Press enter to continue..."
            prod_env_menu
            ;;
        2)
            # Confirmation for production deployment
            read -p "Are you sure you want to deploy to production? (y/n): " confirm
            if [ "$confirm" = "y" ]; then
                deploy_infrastructure "prod" "apply"
            else
                print_warning "Deployment to production aborted."
            fi
            read -p "Press enter to continue..."
            prod_env_menu
            ;;
        3)
            show_k8s_resources "prod"
            read -p "Press enter to continue..."
            prod_env_menu
            ;;
        4)
            get_pod_logs "prod"
            read -p "Press enter to continue..."
            prod_env_menu
            ;;
        5)
            restart_deployments "prod"
            read -p "Press enter to continue..."
            prod_env_menu
            ;;
        6)
            shell_into_pod "prod"
            prod_env_menu
            ;;
        7)
            check_ssl_status "prod"
            read -p "Press enter to continue..."
            prod_env_menu
            ;;
        8)
            cleanup_resources "prod"
            read -p "Press enter to continue..."
            prod_env_menu
            ;;
        9)
            main_menu
            ;;
        *)
            print_error "Invalid choice. Please try again."
            prod_env_menu
            ;;
    esac
}

# Local development menu
local_dev_menu() {
    clear
    print_header "Local Development"
    echo "1. Run application (run.sh)"
    echo "2. Run Rust service (run_rust.sh)"
    echo "3. Deploy locally (deploy.sh)"
    echo "4. Back to main menu"
    echo ""
    read -p "Enter your choice [1-4]: " local_choice
    
    case $local_choice in
        1)
            run_local_app
            read -p "Press enter to continue..."
            local_dev_menu
            ;;
        2)
            run_rust_service
            read -p "Press enter to continue..."
            local_dev_menu
            ;;
        3)
            deploy_local
            read -p "Press enter to continue..."
            local_dev_menu
            ;;
        4)
            main_menu
            ;;
        *)
            print_error "Invalid choice. Please try again."
            local_dev_menu
            ;;
    esac
}

# Tools and setup menu
tools_menu() {
    clear
    print_header "Tools & Setup"
    echo "1. Install required tools (requires sudo)"
    echo "2. Set up development environment"
    echo "3. Set up production environment"
    echo "4. Back to main menu"
    echo ""
    read -p "Enter your choice [1-4]: " tools_choice
    
    case $tools_choice in
        1)
            sudo $0 install
            read -p "Press enter to continue..."
            tools_menu
            ;;
        2)
            setup_environment "dev"
            read -p "Press enter to continue..."
            tools_menu
            ;;
        3)
            setup_environment "prod"
            read -p "Press enter to continue..."
            tools_menu
            ;;
        4)
            main_menu
            ;;
        *)
            print_error "Invalid choice. Please try again."
            tools_menu
            ;;
    esac
}

# PART 6: COMMAND LINE INTERFACE
# --------------------------------------

# Main script - Command line interface
if [ $# -eq 0 ]; then
    # No arguments, show the menu
    main_menu
else
    # Process command line arguments
    case "$1" in
        "menu")
            main_menu
            ;;
        "deploy")
            if [ $# -lt 2 ]; then
                print_error "Missing environment parameter."
                show_help
                exit 1
            fi
            if [ $# -eq 3 ]; then
                deploy_infrastructure "$2" "$3"
            else
                deploy_infrastructure "$2"
            fi
            ;;
        "kustomize")
            if [ $# -lt 2 ]; then
                print_error "Missing environment parameter."
                show_help
                exit 1
            fi
            deploy_kustomize "$2"
            ;;
        "install")
            install_tools
            ;;
        "setup")
            if [ $# -lt 2 ]; then
                print_error "Missing environment parameter."
                show_help
                exit 1
            fi
            setup_environment "$2"
            ;;
        "status")
            if [ $# -lt 2 ]; then
                print_error "Missing environment parameter."
                show_help
                exit 1
            fi
            show_k8s_resources "$2"
            ;;
        "logs")
            if [ $# -lt 2 ]; then
                print_error "Missing environment parameter."
                show_help
                exit 1
            fi
            get_pod_logs "$2"
            ;;
        "ssl-status")
            if [ $# -lt 2 ]; then
                print_error "Missing environment parameter."
                show_help
                exit 1
            fi
            check_ssl_status "$2"
            ;;
        "shell")
            if [ $# -lt 2 ]; then
                print_error "Missing environment parameter."
                show_help
                exit 1
            fi
            shell_into_pod "$2"
            ;;
        "restart")
            if [ $# -lt 2 ]; then
                print_error "Missing environment parameter."
                show_help
                exit 1
            fi
            restart_deployments "$2"
            ;;
        "cleanup")
            if [ $# -lt 2 ]; then
                print_error "Missing environment parameter."
                show_help
                exit 1
            fi
            cleanup_resources "$2"
            ;;
        "run-local")
            run_local_app
            ;;
        "run-rust")
            run_rust_service
            ;;
        "deploy-local")
            deploy_local
            ;;
        "--help"|"-h"|"help")
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
fi