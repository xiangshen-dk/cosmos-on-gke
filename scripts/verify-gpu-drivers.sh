#!/bin/bash

# GPU Driver Verification Script
# This script verifies NVIDIA GPU drivers are properly installed and functioning

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

# Check GPU driver pods
check_driver_pods() {
    print_info "Checking NVIDIA driver installer pods..."
    
    local driver_pods=$(kubectl get pods -n kube-system -l k8s-app=nvidia-driver-installer --no-headers 2>/dev/null | wc -l)
    
    if [ "$driver_pods" -eq 0 ]; then
        print_error "No NVIDIA driver installer pods found."
        print_info "Installing NVIDIA drivers..."
        kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded-latest.yaml
        sleep 10
    fi
    
    # Show driver pod status
    kubectl get pods -n kube-system -l k8s-app=nvidia-driver-installer
    
    # Wait for all driver pods to be ready
    print_info "Waiting for driver pods to be ready..."
    kubectl wait --for=condition=ready pod -l k8s-app=nvidia-driver-installer -n kube-system --timeout=300s || {
        print_warning "Some driver pods may not be ready yet. Continuing..."
    }
}

# Check GPU device plugin
check_device_plugin() {
    print_info "Checking NVIDIA device plugin..."
    
    local device_plugin=$(kubectl get pods -n kube-system -l k8s-app=nvidia-gpu-device-plugin --no-headers 2>/dev/null | wc -l)
    
    if [ "$device_plugin" -eq 0 ]; then
        print_info "Installing NVIDIA device plugin..."
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/device-plugins/nvidia-gpu/daemonset.yaml
        sleep 10
    fi
    
    # Show device plugin status
    kubectl get pods -n kube-system -l k8s-app=nvidia-gpu-device-plugin 2>/dev/null || {
        print_warning "NVIDIA device plugin not found or not labeled correctly."
    }
}

# Check GPU nodes
check_gpu_nodes() {
    print_info "Checking GPU nodes..."
    
    # Get nodes with GPUs
    local gpu_nodes=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.allocatable."nvidia.com/gpu" != null) | .metadata.name')
    
    if [ -z "$gpu_nodes" ]; then
        print_warning "No nodes with GPUs found yet."
        print_info "GPU nodes may still be initializing. Please wait a few minutes."
    else
        print_info "Nodes with GPUs:"
        echo "$gpu_nodes"
        
        # Show GPU allocatable resources
        print_info "GPU resources per node:"
        for node in $gpu_nodes; do
            local gpu_count=$(kubectl get node $node -o json | jq -r '.status.allocatable."nvidia.com/gpu" // "0"')
            echo "  $node: $gpu_count GPU(s)"
        done
    fi
}

# Test GPU functionality
test_gpu_pod() {
    print_info "Testing GPU functionality with a test pod..."
    
    # Create test pod manifest
    cat > /tmp/gpu-test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  restartPolicy: OnFailure
  containers:
  - name: cuda-test
    image: nvidia/cuda:11.8.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
    
    # Delete existing test pod if any
    kubectl delete pod gpu-test --ignore-not-found=true
    
    # Create test pod
    kubectl apply -f /tmp/gpu-test-pod.yaml
    
    # Wait for pod to complete
    print_info "Waiting for GPU test pod to complete..."
    kubectl wait --for=jsonpath={.status.phase}=Succeeded pod/gpu-test --timeout=120s || {
        print_warning "Test pod did not complete in time. Checking status..."
        kubectl describe pod gpu-test
        return 1
    }
    
    # Get pod logs
    print_info "GPU test results:"
    kubectl logs gpu-test
    
    # Clean up
    kubectl delete pod gpu-test
    rm -f /tmp/gpu-test-pod.yaml
    
    print_info "GPU test completed successfully!"
}

# Check cluster autoscaler
check_autoscaler() {
    print_info "Checking cluster autoscaler status..."
    
    kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml 2>/dev/null || {
        print_warning "Cluster autoscaler status not available."
    }
}

# Main execution
main() {
    print_info "Starting GPU driver verification..."
    
    # Check if kubectl is configured
    if ! kubectl cluster-info &> /dev/null; then
        print_error "kubectl is not configured. Please run 'gcloud container clusters get-credentials' first."
        exit 1
    fi
    
    check_driver_pods
    check_device_plugin
    check_gpu_nodes
    
    # Only test GPU if nodes are available
    local gpu_count=$(kubectl get nodes -o json | jq '[.items[].status.allocatable."nvidia.com/gpu" // 0 | tonumber] | add')
    if [ "$gpu_count" -gt 0 ]; then
        test_gpu_pod
    else
        print_warning "No GPUs available yet. Skipping GPU test."
        print_info "Run this script again in a few minutes when GPU nodes are ready."
    fi
    
    check_autoscaler
    
    print_info "GPU driver verification completed!"
}

# Run main function
main "$@"