#!/bin/bash

# GKE Cluster Creation Script for NVIDIA Cosmos
# This script creates a GKE cluster with GPU nodes for inference workloads

set -e

# Configuration variables
PROJECT_ID="${GCP_PROJECT_ID:-your-project-id}"
CLUSTER_NAME="${CLUSTER_NAME:-cosmos-gpu-cluster}"
REGION="${GCP_REGION:-us-central1}"
ZONE="${GCP_ZONE:-us-central1-a}"
MACHINE_TYPE="${MACHINE_TYPE:-a2-ultragpu-1g}"
GPU_TYPE="${GPU_TYPE:-nvidia-a100-80gb}"
GPU_COUNT="${GPU_COUNT:-1}"
NUM_NODES="${NUM_NODES:-2}"
MIN_NODES="${MIN_NODES:-1}"
MAX_NODES="${MAX_NODES:-4}"
DISK_SIZE="${DISK_SIZE:-400}"
K8S_VERSION="${K8S_VERSION:-latest}"

# VPC Configuration
VPC_NAME="${VPC_NAME:-cosmos-vpc}"
SUBNET_NAME="${SUBNET_NAME:-cosmos-subnet}"
SUBNET_RANGE="${SUBNET_RANGE:-10.0.0.0/24}"
PODS_RANGE="${PODS_RANGE:-10.1.0.0/16}"
SERVICES_RANGE="${SERVICES_RANGE:-10.2.0.0/16}"

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

# Check if required tools are installed
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl."
        exit 1
    fi
    
    print_info "Prerequisites check passed."
}

# Validate GCP project
validate_project() {
    print_info "Validating GCP project..."
    
    if [ "$PROJECT_ID" = "your-project-id" ]; then
        print_error "Please set GCP_PROJECT_ID environment variable or update PROJECT_ID in the script."
        exit 1
    fi
    
    gcloud config set project $PROJECT_ID
    
    if ! gcloud projects describe $PROJECT_ID &> /dev/null; then
        print_error "Project $PROJECT_ID not found or you don't have access."
        exit 1
    fi
    
    print_info "Using project: $PROJECT_ID"
}

# Enable required APIs
enable_apis() {
    print_info "Enabling required GCP APIs..."
    
    gcloud services enable compute.googleapis.com
    gcloud services enable container.googleapis.com
    gcloud services enable containerregistry.googleapis.com
    
    print_info "APIs enabled successfully."
}

# Create VPC network
create_vpc() {
    print_info "Creating VPC network: $VPC_NAME"
    
    # Check if VPC already exists
    if gcloud compute networks describe $VPC_NAME &> /dev/null; then
        print_warning "VPC $VPC_NAME already exists. Skipping creation."
        return
    fi
    
    # Create VPC network
    gcloud compute networks create $VPC_NAME \
        --subnet-mode=custom \
        --bgp-routing-mode=regional \
        --project=$PROJECT_ID
    
    print_info "VPC network created successfully."
}

# Create subnet
create_subnet() {
    print_info "Creating subnet: $SUBNET_NAME"
    
    # Check if subnet already exists
    if gcloud compute networks subnets describe $SUBNET_NAME --region=$REGION &> /dev/null; then
        print_warning "Subnet $SUBNET_NAME already exists. Skipping creation."
        return
    fi
    
    # Create subnet with secondary ranges for pods and services
    gcloud compute networks subnets create $SUBNET_NAME \
        --network=$VPC_NAME \
        --region=$REGION \
        --range=$SUBNET_RANGE \
        --secondary-range=pods=$PODS_RANGE \
        --secondary-range=services=$SERVICES_RANGE \
        --enable-private-ip-google-access \
        --project=$PROJECT_ID
    
    print_info "Subnet created successfully with secondary ranges for pods and services."
}

# Create firewall rules
create_firewall_rules() {
    print_info "Creating firewall rules..."
    
    # Allow internal communication
    if ! gcloud compute firewall-rules describe $VPC_NAME-allow-internal &> /dev/null; then
        gcloud compute firewall-rules create $VPC_NAME-allow-internal \
            --network=$VPC_NAME \
            --allow=tcp,udp,icmp \
            --source-ranges=$SUBNET_RANGE,$PODS_RANGE,$SERVICES_RANGE \
            --project=$PROJECT_ID
        print_info "Internal firewall rule created."
    else
        print_warning "Internal firewall rule already exists."
    fi
    
    # Allow SSH
    if ! gcloud compute firewall-rules describe $VPC_NAME-allow-ssh &> /dev/null; then
        gcloud compute firewall-rules create $VPC_NAME-allow-ssh \
            --network=$VPC_NAME \
            --allow=tcp:22 \
            --source-ranges=0.0.0.0/0 \
            --project=$PROJECT_ID
        print_info "SSH firewall rule created."
    else
        print_warning "SSH firewall rule already exists."
    fi
}

# Create GKE cluster
create_cluster() {
    print_info "Creating GKE cluster: $CLUSTER_NAME"
    
    # Check if cluster already exists
    if gcloud container clusters describe $CLUSTER_NAME --zone=$ZONE &> /dev/null; then
        print_warning "Cluster $CLUSTER_NAME already exists. Skipping creation."
        return
    fi
    
    # Create cluster without GPU nodes first
    gcloud container clusters create $CLUSTER_NAME \
        --zone=$ZONE \
        --network=$VPC_NAME \
        --subnetwork=$SUBNET_NAME \
        --cluster-secondary-range-name=pods \
        --services-secondary-range-name=services \
        --enable-ip-alias \
        --num-nodes=1 \
        --enable-autoscaling \
        --min-nodes=1 \
        --max-nodes=2 \
        --machine-type=e2-standard-4 \
        --disk-size=50 \
        --enable-autorepair \
        --enable-autoupgrade \
        --release-channel=regular \
        --workload-pool=$PROJECT_ID.svc.id.goog \
        --addons=GcePersistentDiskCsiDriver
    
    print_info "Base cluster created successfully."
}

# Create GPU node pool
create_gpu_node_pool() {
    print_info "Creating GPU node pool..."
    
    # Check if node pool already exists
    if gcloud container node-pools describe gpu-pool --cluster=$CLUSTER_NAME --zone=$ZONE &> /dev/null 2>&1; then
        print_warning "GPU node pool already exists. Skipping creation."
        return
    fi
    
    gcloud container node-pools create gpu-pool \
        --cluster=$CLUSTER_NAME \
        --zone=$ZONE \
        --machine-type=$MACHINE_TYPE \
        --accelerator=type=$GPU_TYPE,count=$GPU_COUNT \
        --num-nodes=$NUM_NODES \
        --min-nodes=$MIN_NODES \
        --max-nodes=$MAX_NODES \
        --enable-autoscaling \
        --enable-autorepair \
        --enable-autoupgrade \
        --disk-size=$DISK_SIZE \
        --disk-type=pd-balanced \
        --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append
    
    print_info "GPU node pool created successfully."
}

# Get cluster credentials
get_credentials() {
    print_info "Getting cluster credentials..."
    
    gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE
    
    print_info "Cluster credentials configured for kubectl."
}

# Install NVIDIA GPU drivers
install_gpu_drivers() {
    print_info "Installing NVIDIA GPU drivers..."
    
    # Apply NVIDIA driver installer DaemonSet
    kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded-latest.yaml
    
    print_info "NVIDIA GPU driver installation initiated. This may take a few minutes."
    
    # Wait for driver installation
    print_info "Waiting for GPU drivers to be installed..."
    kubectl wait --for=condition=ready pod -l k8s-app=nvidia-driver-installer --timeout=300s -n kube-system || true
}

# Verify GPU availability
verify_gpu() {
    print_info "Verifying GPU availability..."
    
    # Wait a bit for nodes to register GPUs
    sleep 30
    
    # Check GPU resources
    local gpu_count=$(kubectl get nodes -o json | jq '[.items[].status.allocatable."nvidia.com/gpu" // 0 | tonumber] | add')
    
    if [ "$gpu_count" -gt 0 ]; then
        print_info "GPUs available in cluster: $gpu_count"
        kubectl describe nodes | grep -A 5 "nvidia.com/gpu"
    else
        print_warning "No GPUs detected yet. They may still be initializing."
        print_warning "Run 'kubectl describe nodes' to check GPU status."
    fi
}

# Main execution
main() {
    print_info "Starting GKE cluster creation for NVIDIA Cosmos..."
    
    check_prerequisites
    validate_project
    enable_apis
    create_vpc
    create_subnet
    create_firewall_rules
    create_cluster
    create_gpu_node_pool
    get_credentials
    install_gpu_drivers
    verify_gpu
    
    print_info "GKE cluster setup completed!"
    print_info "Cluster name: $CLUSTER_NAME"
    print_info "Zone: $ZONE"
    print_info "GPU type: $GPU_TYPE"
    print_info "GPU count per node: $GPU_COUNT"
    print_info "Number of GPU nodes: $NUM_NODES"
    
    echo ""
    print_info "Next steps:"
    echo "1. Wait for GPU drivers to fully initialize (2-5 minutes)"
    echo "2. Run './deploy-cosmos.sh' to deploy NVIDIA Cosmos"
    echo "3. Monitor GPU node status: kubectl get nodes -l cloud.google.com/gke-accelerator=$GPU_TYPE"
}

# Run main function
main "$@"
