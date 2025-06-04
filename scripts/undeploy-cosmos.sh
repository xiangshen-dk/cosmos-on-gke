#!/bin/bash

# NVIDIA Cosmos Undeploy Script
# This script removes NVIDIA Cosmos deployment from GKE

set -e

# Configuration
NAMESPACE="${COSMOS_NAMESPACE:-cosmos}"

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

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "kubectl is not configured or cluster is not accessible."
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        print_warning "Namespace '$NAMESPACE' does not exist. Nothing to undeploy."
        exit 0
    fi
    
    print_info "Connected to cluster and namespace '$NAMESPACE' exists."
}

# Delete Cosmos deployment and related resources
delete_cosmos_resources() {
    print_info "Deleting Cosmos resources in namespace '$NAMESPACE'..."
    
    # Delete PodDisruptionBudget
    print_info "Deleting PodDisruptionBudget..."
    kubectl delete pdb cosmos-pdb -n $NAMESPACE --ignore-not-found=true
    
    # Delete HorizontalPodAutoscaler
    print_info "Deleting HorizontalPodAutoscaler..."
    kubectl delete hpa cosmos-hpa -n $NAMESPACE --ignore-not-found=true
    
    # Delete Service
    print_info "Deleting Service..."
    kubectl delete service cosmos-service -n $NAMESPACE --ignore-not-found=true
    
    # Delete Deployment
    print_info "Deleting Deployment..."
    kubectl delete deployment cosmos-inference -n $NAMESPACE --ignore-not-found=true
    
    # Wait for pods to terminate
    print_info "Waiting for pods to terminate..."
    kubectl wait --for=delete pod -l app=cosmos -n $NAMESPACE --timeout=60s || true
    
    # Delete ConfigMap
    print_info "Deleting ConfigMap..."
    kubectl delete configmap cosmos-config -n $NAMESPACE --ignore-not-found=true
    
    # Delete PersistentVolumeClaim
    print_info "Deleting PersistentVolumeClaim..."
    kubectl delete pvc cosmos-model-storage -n $NAMESPACE --ignore-not-found=true
}

# Delete namespace (optional)
delete_namespace() {
    read -p "Do you want to delete the namespace '$NAMESPACE'? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deleting namespace '$NAMESPACE'..."
        kubectl delete namespace $NAMESPACE --ignore-not-found=true
        
        # Wait for namespace deletion
        print_info "Waiting for namespace deletion to complete..."
        while kubectl get namespace $NAMESPACE &> /dev/null; do
            sleep 2
        done
        print_info "Namespace deleted successfully."
    else
        print_info "Namespace '$NAMESPACE' retained."
    fi
}

# Show remaining resources
show_remaining_resources() {
    print_info "Checking for any remaining resources..."
    
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        echo ""
        print_info "Resources in namespace '$NAMESPACE':"
        kubectl get all -n $NAMESPACE
        
        echo ""
        print_info "PersistentVolumeClaims:"
        kubectl get pvc -n $NAMESPACE
        
        echo ""
        print_info "ConfigMaps:"
        kubectl get configmap -n $NAMESPACE
    else
        print_info "Namespace '$NAMESPACE' has been deleted."
    fi
}

# Main execution
main() {
    print_info "Starting NVIDIA Cosmos undeployment..."
    echo ""
    print_warning "This will delete all Cosmos resources in namespace '$NAMESPACE'."
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Undeployment cancelled."
        exit 0
    fi
    
    check_prerequisites
    delete_cosmos_resources
    delete_namespace
    show_remaining_resources
    
    print_info "NVIDIA Cosmos undeployment completed!"
    echo ""
    print_info "Note: The GKE cluster and GPU nodes are still running."
    print_info "To delete the entire cluster, run './cleanup-cluster.sh'"
}

# Run main function
main "$@"
