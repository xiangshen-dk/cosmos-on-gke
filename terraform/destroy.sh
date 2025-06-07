#!/bin/bash

# Terraform destroy script for GKE infrastructure
# This script destroys the GKE cluster and related infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "main.tf" ]; then
    print_error "Please run this script from the terraform/environments/prod directory"
    exit 1
fi

# Initialize Terraform (required to read state and providers)
print_info "Initializing Terraform..."
terraform init

# Check if Cosmos application is still deployed
print_info "Checking for Cosmos application deployment..."
if terraform state list | grep -q "google_container_cluster"; then
    # Get cluster credentials
    CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    if [ -n "$CLUSTER_NAME" ]; then
        ZONE=$(grep -E "^zone\s*=" terraform.tfvars | cut -d'"' -f2 || echo "us-central1-a")
        PROJECT_ID=$(grep -E "^project_id\s*=" terraform.tfvars | cut -d'"' -f2)
        
        print_info "Configuring kubectl for cluster: $CLUSTER_NAME"
        if gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" 2>/dev/null; then
            # Check if Cosmos namespace exists
            if kubectl get namespace cosmos 2>/dev/null; then
                print_warning "Cosmos application is still deployed!"
                print_warning "Please remove it first to avoid orphaned resources:"
                echo "     kubectl delete -f ../../../kubernetes/cosmos/"
                echo ""
                read -p "Do you want to continue anyway? (y/N) " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    print_info "Destruction cancelled."
                    exit 0
                fi
            fi
        fi
    fi
fi

# Destroy GKE infrastructure
print_info "Destroying GKE infrastructure..."
print_info "This will destroy the VPC, GKE cluster, and GPU node pools."

# Confirm destruction
print_warning "This will permanently destroy all infrastructure!"
read -p "Are you sure you want to continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Destruction cancelled."
    exit 0
fi

# Destroy everything
terraform destroy -auto-approve

print_info "All infrastructure destroyed successfully!"
print_info ""
print_info "Note: If you had Cosmos deployed, its PersistentVolumes may still exist in GCP."
print_info "Check for orphaned disks in the GCP Console if needed."
