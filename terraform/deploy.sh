#!/bin/bash

# Terraform deployment script for GKE infrastructure
# This script deploys the GKE cluster for running NVIDIA Cosmos

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

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    print_error "terraform.tfvars not found. Please copy terraform.tfvars.example and configure it."
    exit 1
fi

# Deploy GKE infrastructure
print_info "Deploying GKE infrastructure..."
print_info "This will create the VPC, GKE cluster, and GPU node pools."

# Initialize and apply Terraform
terraform init
terraform apply -auto-approve

print_info "GKE infrastructure deployed successfully!"

# Get cluster information
CLUSTER_NAME=$(terraform output -raw cluster_name)
ZONE=$(grep -E "^zone\s*=" terraform.tfvars | cut -d'"' -f2 || echo "us-central1-a")
PROJECT_ID=$(grep -E "^project_id\s*=" terraform.tfvars | cut -d'"' -f2)

print_info "Getting cluster credentials..."
gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE --project=$PROJECT_ID

# Wait for cluster to be fully ready
print_info "Waiting for cluster API to be responsive..."
for i in {1..30}; do
    if kubectl cluster-info &> /dev/null; then
        print_info "Cluster is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "Timeout waiting for cluster to be ready"
        exit 1
    fi
    echo -n "."
    sleep 10
done

# Wait for nodes to be ready
print_info "Waiting for GPU nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=600s || true

# Check GPU nodes
print_info "Checking GPU nodes..."
kubectl get nodes -l cloud.google.com/gke-accelerator

print_info ""
print_info "GKE infrastructure deployment complete!"
print_info ""
print_info "Next steps:"
print_info "1. Deploy Cosmos application using Kubernetes manifests:"
echo "     cd ../../../kubernetes"
echo "     ./deploy-cosmos.sh -t YOUR_HF_TOKEN -c $CLUSTER_NAME -z $ZONE -p $PROJECT_ID"
print_info ""
print_info "2. Monitor the deployment:"
echo "     kubectl get pods -n cosmos -w"
print_info ""
print_info "See kubernetes/README.md for detailed instructions."
