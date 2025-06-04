#!/bin/bash

# GKE Cluster Cleanup Script
# This script removes the GKE cluster and associated resources

set -e

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-your-project-id}"
CLUSTER_NAME="${CLUSTER_NAME:-cosmos-gpu-cluster}"
ZONE="${GCP_ZONE:-us-central1-a}"
NAMESPACE="${COSMOS_NAMESPACE:-cosmos}"
REGION="${GCP_REGION:-us-central1}"

# VPC Configuration
VPC_NAME="${VPC_NAME:-cosmos-vpc}"
SUBNET_NAME="${SUBNET_NAME:-cosmos-subnet}"

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

# Confirmation prompt
confirm_deletion() {
    print_warning "This will delete the following resources:"
    echo "  - GKE Cluster: $CLUSTER_NAME"
    echo "  - Zone: $ZONE"
    echo "  - All workloads in namespace: $NAMESPACE"
    echo "  - All associated persistent volumes"
    echo "  - VPC network: $VPC_NAME"
    echo "  - Subnet: $SUBNET_NAME"
    echo "  - Associated firewall rules"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        print_info "Cleanup cancelled."
        exit 0
    fi
}

# Delete Cosmos deployment
delete_cosmos_deployment() {
    print_info "Deleting Cosmos deployment..."
    
    # Check if namespace exists
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        # Delete all resources in namespace
        kubectl delete all --all -n $NAMESPACE --grace-period=30
        
        # Delete PVCs
        kubectl delete pvc --all -n $NAMESPACE
        
        # Delete ConfigMaps and Secrets
        kubectl delete configmap --all -n $NAMESPACE
        kubectl delete secret --all -n $NAMESPACE
        
        # Delete namespace
        kubectl delete namespace $NAMESPACE
        
        print_info "Cosmos deployment deleted."
    else
        print_warning "Namespace $NAMESPACE not found. Skipping Cosmos deletion."
    fi
}

# Delete any remaining PersistentVolumes
delete_persistent_volumes() {
    print_info "Checking for persistent volumes..."
    
    # Get PVs associated with our cluster
    local pvs=$(kubectl get pv -o json | jq -r '.items[] | select(.spec.claimRef.namespace == "'$NAMESPACE'") | .metadata.name')
    
    if [ -n "$pvs" ]; then
        print_info "Deleting persistent volumes..."
        for pv in $pvs; do
            kubectl delete pv $pv --grace-period=0 --force
        done
    fi
}

# Delete GKE cluster
delete_gke_cluster() {
    print_info "Deleting GKE cluster: $CLUSTER_NAME"
    
    # Check if cluster exists
    if gcloud container clusters describe $CLUSTER_NAME --zone=$ZONE &> /dev/null; then
        gcloud container clusters delete $CLUSTER_NAME \
            --zone=$ZONE \
            --quiet
        
        print_info "GKE cluster deleted successfully."
    else
        print_warning "Cluster $CLUSTER_NAME not found in zone $ZONE."
    fi
}

# Clean up firewall rules
cleanup_firewall_rules() {
    print_info "Cleaning up firewall rules..."
    
    # List firewall rules created by GKE
    local gke_firewall_rules=$(gcloud compute firewall-rules list --filter="name~'gke-$CLUSTER_NAME'" --format="get(name)")
    
    if [ -n "$gke_firewall_rules" ]; then
        print_info "Deleting GKE firewall rules..."
        for rule in $gke_firewall_rules; do
            gcloud compute firewall-rules delete $rule --quiet || true
        done
    fi
    
    # Delete VPC firewall rules
    local vpc_firewall_rules=$(gcloud compute firewall-rules list --filter="network:$VPC_NAME" --format="get(name)")
    
    if [ -n "$vpc_firewall_rules" ]; then
        print_info "Deleting VPC firewall rules..."
        for rule in $vpc_firewall_rules; do
            gcloud compute firewall-rules delete $rule --quiet || true
        done
    fi
}

# Clean up any remaining disks
cleanup_disks() {
    print_info "Checking for orphaned disks..."
    
    # List disks that might be orphaned
    local disks=$(gcloud compute disks list --filter="name~'gke-$CLUSTER_NAME' AND -users:*" --format="get(name,zone)")
    
    if [ -n "$disks" ]; then
        print_warning "Found potentially orphaned disks. Please review and delete manually if needed:"
        echo "$disks"
    fi
}

# Remove kubectl context
remove_kubectl_context() {
    print_info "Removing kubectl context..."
    
    local context_name="gke_${PROJECT_ID}_${ZONE}_${CLUSTER_NAME}"
    kubectl config delete-context $context_name 2>/dev/null || true
    
    print_info "kubectl context removed."
}

# Delete subnet
delete_subnet() {
    print_info "Deleting subnet: $SUBNET_NAME"
    
    # Check if subnet exists
    if gcloud compute networks subnets describe $SUBNET_NAME --region=$REGION &> /dev/null 2>&1; then
        gcloud compute networks subnets delete $SUBNET_NAME \
            --region=$REGION \
            --quiet
        
        print_info "Subnet deleted successfully."
    else
        print_warning "Subnet $SUBNET_NAME not found in region $REGION."
    fi
}

# Delete VPC network
delete_vpc() {
    print_info "Deleting VPC network: $VPC_NAME"
    
    # Check if VPC exists
    if gcloud compute networks describe $VPC_NAME &> /dev/null 2>&1; then
        gcloud compute networks delete $VPC_NAME \
            --quiet
        
        print_info "VPC network deleted successfully."
    else
        print_warning "VPC $VPC_NAME not found."
    fi
}

# Main execution
main() {
    print_info "Starting GKE cluster cleanup..."
    
    # Check prerequisites
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed."
        exit 1
    fi
    
    # Set project
    if [ "$PROJECT_ID" != "your-project-id" ]; then
        gcloud config set project $PROJECT_ID
    else
        print_error "Please set GCP_PROJECT_ID environment variable."
        exit 1
    fi
    
    # Confirm deletion
    confirm_deletion
    
    # Try to delete Cosmos deployment first if cluster is accessible
    if kubectl cluster-info &> /dev/null 2>&1; then
        delete_cosmos_deployment
        delete_persistent_volumes
    fi
    
    # Delete GKE cluster
    delete_gke_cluster
    
    # Cleanup additional resources
    cleanup_firewall_rules
    cleanup_disks
    remove_kubectl_context
    
    # Delete VPC resources
    print_info "Waiting for cluster resources to be fully released..."
    sleep 10
    delete_subnet
    delete_vpc
    
    print_info "Cleanup completed!"
    print_info "Note: Some resources like Load Balancer IPs may take a few minutes to be fully released."
}

# Run main function
main "$@"
