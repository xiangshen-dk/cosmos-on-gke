#!/bin/bash

# Cosmos Kubernetes Cleanup Script
# This script removes the Cosmos application from a GKE cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="cosmos"
CLUSTER_NAME=""
ZONE=""
PROJECT_ID=""
FORCE=false
DELETE_PVCS=false

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -c, --cluster NAME      GKE cluster name (required)"
    echo "  -z, --zone ZONE        GKE cluster zone (required)"
    echo "  -p, --project PROJECT   GCP project ID (required)"
    echo "  -f, --force            Skip confirmation prompts"
    echo "  --delete-pvcs          Also delete PersistentVolumeClaims (data will be lost!)"
    echo ""
    echo "Example:"
    echo "  $0 -c cosmos-cluster -z us-central1-a -p my-project"
    echo ""
    echo "  # Force deletion including PVCs"
    echo "  $0 -c cosmos-cluster -z us-central1-a -p my-project -f --delete-pvcs"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_ID="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --delete-pvcs)
            DELETE_PVCS=true
            shift
            ;;
        *)
            print_message $RED "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "$CLUSTER_NAME" ]] || [[ -z "$ZONE" ]] || [[ -z "$PROJECT_ID" ]]; then
    print_message $RED "Error: Cluster name, zone, and project ID are required"
    usage
fi

# Get cluster credentials
print_message $YELLOW "Getting cluster credentials..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID"

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_message $YELLOW "Namespace '$NAMESPACE' does not exist. Nothing to clean up."
    exit 0
fi

# Show what will be deleted
print_message $YELLOW "The following resources will be deleted from namespace '$NAMESPACE':"
echo ""
kubectl get all -n "$NAMESPACE" 2>/dev/null || true
echo ""
kubectl get pvc -n "$NAMESPACE" 2>/dev/null || true
echo ""
kubectl get configmap,secret -n "$NAMESPACE" 2>/dev/null || true
echo ""

# Confirmation prompt
if [[ "$FORCE" != true ]]; then
    print_message $YELLOW "Are you sure you want to delete all Cosmos resources?"
    if [[ "$DELETE_PVCS" == true ]]; then
        print_message $RED "WARNING: This will also delete PersistentVolumeClaims and their data!"
    else
        print_message $YELLOW "Note: PersistentVolumeClaims will be preserved by default."
    fi
    read -p "Type 'yes' to continue: " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        print_message $YELLOW "Cleanup cancelled."
        exit 0
    fi
fi

# Delete all resources with the app=cosmos label
print_message $YELLOW "Deleting all Cosmos application resources..."
kubectl delete all,configmap,secret -l app=cosmos -n "$NAMESPACE" --ignore-not-found=true

# Wait for pods to terminate to ensure a clean deletion
print_message $YELLOW "Waiting for pods to terminate..."
kubectl wait --for=delete pod -l app=cosmos -n "$NAMESPACE" --timeout=120s 2>/dev/null || true

# Delete PVCs if requested
if [[ "$DELETE_PVCS" == true ]]; then
    print_message $YELLOW "Deleting PersistentVolumeClaims..."
    kubectl delete pvc cosmos-model-storage cosmos-cache-storage -n "$NAMESPACE" --ignore-not-found=true
    
    # Wait for PVCs to be deleted
    print_message $YELLOW "Waiting for PVCs to be deleted..."
    kubectl wait --for=delete pvc cosmos-model-storage cosmos-cache-storage -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
else
    print_message $GREEN "PersistentVolumeClaims preserved. To delete them later, run:"
    echo "  kubectl delete pvc cosmos-model-storage cosmos-cache-storage -n $NAMESPACE"
fi

# Delete namespace (only if empty or force delete)
if kubectl get all -n "$NAMESPACE" 2>&1 | grep -q "No resources found"; then
    print_message $YELLOW "Deleting namespace..."
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
else
    print_message $YELLOW "Namespace '$NAMESPACE' still contains resources. Not deleting namespace."
fi

print_message $GREEN "Cosmos cleanup completed successfully!"

# Show remaining resources if any
REMAINING=$(kubectl get all,pvc -n "$NAMESPACE" 2>&1 | grep -v "No resources found" | grep -v "NAME" | wc -l)
if [[ $REMAINING -gt 0 ]]; then
    print_message $YELLOW ""
    print_message $YELLOW "Remaining resources in namespace '$NAMESPACE':"
    kubectl get all,pvc -n "$NAMESPACE"
fi

# Check for orphaned PersistentVolumes
print_message $YELLOW ""
print_message $YELLOW "Checking for orphaned PersistentVolumes..."
ORPHANED_PVS=$(kubectl get pv | grep "$NAMESPACE" | grep -E "Released|Failed" | awk '{print $1}')
if [[ -n "$ORPHANED_PVS" ]]; then
    print_message $YELLOW "Found orphaned PersistentVolumes:"
    echo "$ORPHANED_PVS"
    print_message $YELLOW "To delete them, run:"
    for pv in $ORPHANED_PVS; do
        echo "  kubectl delete pv $pv"
    done
else
    print_message $GREEN "No orphaned PersistentVolumes found."
fi
