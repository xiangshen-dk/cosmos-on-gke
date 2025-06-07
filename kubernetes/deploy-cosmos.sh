#!/bin/bash

# Cosmos Kubernetes Deployment Script
# This script deploys the Cosmos application to a GKE cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="cosmos"
HF_TOKEN=""
CLUSTER_NAME=""
ZONE=""
PROJECT_ID=""
GPU_TYPE="nvidia-a100-80gb"
MODEL_ID="nvidia/Cosmos-1.0-Diffusion-7B-Text2World"
IMAGE="us-docker.pkg.dev/vertex-ai/vertex-vision-model-garden-dockers/pytorch-cosmos:20250314"
MODEL_STORAGE="150Gi"
CACHE_STORAGE="100Gi"
REPLICAS="1"

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
    echo "  -h, --help                Show this help message"
    echo "  -t, --token TOKEN         HuggingFace token (required)"
    echo "  -c, --cluster NAME        GKE cluster name (required)"
    echo "  -z, --zone ZONE          GKE cluster zone (required)"
    echo "  -p, --project PROJECT     GCP project ID (required)"
    echo "  -g, --gpu-type TYPE       GPU type (default: nvidia-a100-80gb)"
    echo "  -m, --model-id ID         Model ID (default: nvidia/Cosmos-1.0-Diffusion-7B-Text2World)"
    echo "  -i, --image IMAGE         Container image (default: us-docker.pkg.dev/vertex-ai/vertex-vision-model-garden-dockers/pytorch-cosmos:20250314)"
    echo "  -s, --model-storage SIZE  Model storage size (default: 150Gi)"
    echo "  -d, --cache-storage SIZE  Cache storage size (default: 100Gi)"
    echo "  -r, --replicas COUNT      Number of replicas (default: 1)"
    echo ""
    echo "Example:"
    echo "  $0 -t YOUR_HF_TOKEN -c cosmos-cluster -z us-central1-a -p my-project"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -t|--token)
            HF_TOKEN="$2"
            shift 2
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
        -g|--gpu-type)
            GPU_TYPE="$2"
            shift 2
            ;;
        -m|--model-id)
            MODEL_ID="$2"
            shift 2
            ;;
        -i|--image)
            IMAGE="$2"
            shift 2
            ;;
        -s|--model-storage)
            MODEL_STORAGE="$2"
            shift 2
            ;;
        -d|--cache-storage)
            CACHE_STORAGE="$2"
            shift 2
            ;;
        -r|--replicas)
            REPLICAS="$2"
            shift 2
            ;;
        *)
            print_message $RED "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "$HF_TOKEN" ]]; then
    print_message $RED "Error: HuggingFace token is required"
    usage
fi

if [[ -z "$CLUSTER_NAME" ]] || [[ -z "$ZONE" ]] || [[ -z "$PROJECT_ID" ]]; then
    print_message $RED "Error: Cluster name, zone, and project ID are required"
    usage
fi

# Get cluster credentials
print_message $YELLOW "Getting cluster credentials..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID"

# Create temporary directory for processed manifests
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy manifests to temp directory
cp -r "$(dirname "$0")/cosmos/"* "$TEMP_DIR/"

# Update the secret with the actual HF token
print_message $YELLOW "Creating HuggingFace token secret..."
HF_TOKEN_BASE64=$(echo -n "$HF_TOKEN" | base64)
sed -i.bak "s/REPLACE_WITH_BASE64_ENCODED_TOKEN/$HF_TOKEN_BASE64/g" "$TEMP_DIR/01-secret.yaml"

# Update deployment with custom values
print_message $YELLOW "Updating deployment configuration..."
sed -i.bak "s|nvidia-a100-80gb|$GPU_TYPE|g" "$TEMP_DIR/04-deployment.yaml"
sed -i.bak "s|nvidia/Cosmos-1.0-Diffusion-7B-Text2World|$MODEL_ID|g" "$TEMP_DIR/04-deployment.yaml"
sed -i.bak "s|us-docker.pkg.dev/vertex-ai/vertex-vision-model-garden-dockers/pytorch-cosmos:20250314|$IMAGE|g" "$TEMP_DIR/04-deployment.yaml"
sed -i.bak "s|replicas: 1|replicas: $REPLICAS|g" "$TEMP_DIR/04-deployment.yaml"

# Update PVC sizes
sed -i.bak "s|storage: 150Gi|storage: $MODEL_STORAGE|g" "$TEMP_DIR/03-pvcs.yaml"
sed -i.bak "s|storage: 100Gi|storage: $CACHE_STORAGE|g" "$TEMP_DIR/03-pvcs.yaml"

# Apply the manifests
print_message $YELLOW "Applying Kubernetes manifests..."
kubectl apply -f "$TEMP_DIR/"

# Wait for deployment to be ready
print_message $YELLOW "Waiting for deployment to be ready (this may take up to 40 minutes for initial model download)..."
kubectl wait --for=condition=available --timeout=2400s deployment/cosmos-inference -n "$NAMESPACE"

# Get the service external IP
print_message $YELLOW "Getting service external IP..."
EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
    print_message $YELLOW "Waiting for external IP to be assigned..."
    EXTERNAL_IP=$(kubectl get svc cosmos-service -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [ -z "$EXTERNAL_IP" ] && sleep 10
done

print_message $GREEN "Deployment completed successfully!"
print_message $GREEN "Cosmos service is available at: http://$EXTERNAL_IP"
print_message $GREEN ""
print_message $GREEN "To check the status of your deployment:"
print_message $GREEN "  kubectl get pods -n $NAMESPACE"
print_message $GREEN ""
print_message $GREEN "To view logs:"
print_message $GREEN "  kubectl logs -f deployment/cosmos-inference -n $NAMESPACE"
print_message $GREEN ""
print_message $GREEN "To scale the deployment:"
print_message $GREEN "  kubectl scale deployment/cosmos-inference --replicas=<count> -n $NAMESPACE"
