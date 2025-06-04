#!/bin/bash

# NVIDIA Cosmos Deployment Script
# This script deploys NVIDIA Cosmos on GKE with proper ephemeral storage handling

set -e

# Configuration
NAMESPACE="${COSMOS_NAMESPACE:-cosmos}"
COSMOS_IMAGE="${COSMOS_IMAGE:-us-docker.pkg.dev/vertex-ai/vertex-vision-model-garden-dockers/pytorch-cosmos:20250314}"
SERVICE_TYPE="${SERVICE_TYPE:-LoadBalancer}"
REPLICAS="${REPLICAS:-1}"
HF_TOKEN="${HF_TOKEN}"
HF_MODEL_ID="${HF_MODEL_ID:-nvidia/Cosmos-1.0-Diffusion-7B-Text2World}"
MODEL_PATH="${MODEL_PATH:-/models}"

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
        print_error "kubectl is not configured. Please run './create-gke-cluster.sh' first."
        exit 1
    fi
    
    # Check for HuggingFace token
    if [ -z "$HF_TOKEN" ]; then
        print_error "HF_TOKEN environment variable is not set."
        print_error "Please set it with your HuggingFace token:"
        print_error "  export HF_TOKEN='your-huggingface-token'"
        exit 1
    fi
    
    # Check for GPU nodes
    local gpu_count=$(kubectl get nodes -o json | jq '[.items[].status.allocatable."nvidia.com/gpu" // 0 | tonumber] | add')
    if [ "$gpu_count" -eq 0 ]; then
        print_error "No GPU nodes found in cluster. Please ensure GPU nodes are ready."
        exit 1
    fi
    
    print_info "Found $gpu_count GPU(s) in the cluster."
}

# Create namespace
create_namespace() {
    print_info "Creating namespace: $NAMESPACE"
    
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
}

# Create HuggingFace credentials
create_hf_credentials() {
    print_info "Creating HuggingFace credentials..."
    
    # Create generic secret for HuggingFace token
    kubectl create secret generic hf-token-secret \
        --namespace=$NAMESPACE \
        --from-literal=HF_TOKEN="$HF_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_info "HuggingFace credentials created successfully."
}

# Create ConfigMap for Cosmos configuration
create_configmap() {
    print_info "Creating Cosmos ConfigMap..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cosmos-config
  namespace: $NAMESPACE
data:
  inference.yaml: |
    model:
      name: "cosmos"
      version: "latest"
    
    inference:
      batch_size: 8
      max_sequence_length: 2048
      gpu_memory_fraction: 0.9
      num_threads: 4
    
    server:
      port: 8080
      workers: 1
      timeout: 300
      max_concurrent_requests: 100
    
    logging:
      level: "INFO"
      format: "json"
EOF
}

# Create PersistentVolumeClaims
create_pvcs() {
    print_info "Creating PersistentVolumeClaims..."
    
    # Model storage PVC
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cosmos-model-storage
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 150Gi
  storageClassName: standard-rwo
EOF

    # Cache storage PVC for runtime cache
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cosmos-cache-storage
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: standard-rwo
EOF
}

# Deploy Cosmos with proper storage configuration
deploy_cosmos() {
    print_info "Deploying NVIDIA Cosmos..."
    print_warning "NOTE: The container will download the model on first deployment, which can take 15-30 minutes."
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cosmos-inference
  namespace: $NAMESPACE
  labels:
    app: cosmos
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: cosmos
  template:
    metadata:
      labels:
        app: cosmos
    spec:
      nodeSelector:
        cloud.google.com/gke-accelerator: nvidia-a100-80gb
      tolerations:
      - key: nvidia.com/gpu
        operator: Equal
        value: "true"
        effect: NoSchedule
      containers:
      - name: cosmos
        image: $COSMOS_IMAGE
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        env:
        - name: MODEL_ID
          value: "$HF_MODEL_ID"
        - name: TASK
          value: "text-to-world"
        - name: HUGGING_FACE_HUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: hf-token-secret
              key: HF_TOKEN
        - name: OFFLOAD_NETWORK
          value: "true"
        - name: OFFLOAD_TOKENIZER
          value: "true"
        - name: OFFLOAD_TEXT_ENCODER_MODEL
          value: "true"
        - name: OFFLOAD_GUARDRAIL_MODELS
          value: "true"
        - name: OFFLOAD_PROMPT_UPSAMPLER
          value: "true"
        # Cache and temp directories
        - name: HF_HOME
          value: "/models/huggingface"
        - name: TRANSFORMERS_CACHE
          value: "/cache/transformers"
        - name: HUGGINGFACE_HUB_CACHE
          value: "/cache/hub"
        - name: TMPDIR
          value: "/cache/tmp"
        - name: TEMP
          value: "/cache/tmp"
        - name: TMP
          value: "/cache/tmp"
        - name: HOME
          value: "/cache/home"
        - name: XDG_CACHE_HOME
          value: "/cache/.cache"
        # GPU settings
        - name: NVIDIA_VISIBLE_DEVICES
          value: "all"
        - name: LD_LIBRARY_PATH
          value: "/usr/local/nvidia/lib64:/usr/local/cuda/lib64"
        resources:
          requests:
            cpu: "8"
            memory: "32Gi"
            nvidia.com/gpu: "1"
          limits:
            cpu: "12"
            memory: "48Gi"
            nvidia.com/gpu: "1"
        volumeMounts:
        - name: model-storage
          mountPath: /models
        - name: cache-storage
          mountPath: /cache
        - name: config
          mountPath: /config
        - name: dshm
          mountPath: /dev/shm
      volumes:
      - name: model-storage
        persistentVolumeClaim:
          claimName: cosmos-model-storage
      - name: cache-storage
        persistentVolumeClaim:
          claimName: cosmos-cache-storage
      - name: config
        configMap:
          name: cosmos-config
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: 2Gi
EOF
}

# Create Service
create_service() {
    print_info "Creating Cosmos Service..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: cosmos-service
  namespace: $NAMESPACE
  labels:
    app: cosmos
spec:
  type: $SERVICE_TYPE
  selector:
    app: cosmos
  ports:
  - name: http
    port: 80
    targetPort: 8080
    protocol: TCP
EOF
}

# Create HorizontalPodAutoscaler
create_hpa() {
    print_info "Creating HorizontalPodAutoscaler..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: cosmos-hpa
  namespace: $NAMESPACE
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: cosmos-inference
  minReplicas: 1
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 120
      policies:
      - type: Percent
        value: 100
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
EOF
}

# Create PodDisruptionBudget
create_pdb() {
    print_info "Creating PodDisruptionBudget..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: cosmos-pdb
  namespace: $NAMESPACE
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: cosmos
EOF
}

# Wait for deployment
wait_for_deployment() {
    print_info "Waiting for Cosmos deployment to be ready..."
    print_warning "This can take 15-30 minutes as the container downloads the model on first deployment."
    print_info "You can monitor progress with: kubectl logs -f deployment/cosmos-inference -n $NAMESPACE"
    
    # Wait for pod to be ready with custom loop
    local ready=false
    local attempts=0
    local max_attempts=80  # 40 minutes max (30 seconds * 80)
    
    while [ "$ready" = false ] && [ $attempts -lt $max_attempts ]; do
        local pod_ready=$(kubectl get pods -n $NAMESPACE -l app=cosmos -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        
        if [ "$pod_ready" = "True" ]; then
            ready=true
            print_info "Cosmos pod is ready!"
        else
            echo -n "."
            sleep 30
            ((attempts++))
            
            # Every 5 minutes, show status
            if [ $((attempts % 10)) -eq 0 ]; then
                echo ""
                print_info "Still waiting... ($(($attempts / 2)) minutes elapsed)"
                kubectl get pods -n $NAMESPACE -l app=cosmos
            fi
        fi
    done
    
    if [ "$ready" = false ]; then
        print_error "Timeout waiting for deployment to be ready after 40 minutes"
        print_info "Check logs with: kubectl logs -f deployment/cosmos-inference -n $NAMESPACE"
        exit 1
    fi
    
    # Get final pod status
    print_info "Cosmos pods status:"
    kubectl get pods -n $NAMESPACE -l app=cosmos
}

# Get service endpoint
get_service_endpoint() {
    print_info "Getting service endpoint..."
    
    if [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
        print_info "Waiting for LoadBalancer IP..."
        local lb_ip=""
        local attempts=0
        while [ -z "$lb_ip" ] && [ $attempts -lt 30 ]; do
            lb_ip=$(kubectl get svc cosmos-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            if [ -z "$lb_ip" ]; then
                sleep 10
                ((attempts++))
            fi
        done
        
        if [ -n "$lb_ip" ]; then
            print_info "Cosmos service is available at:"
            echo "  HTTP: http://$lb_ip"
            echo "  gRPC: $lb_ip:8081"
            echo "  Metrics: http://$lb_ip:9090/metrics"
        else
            print_warning "LoadBalancer IP not assigned yet. Check with: kubectl get svc -n $NAMESPACE"
        fi
    else
        print_info "To access Cosmos, use port-forward:"
        echo "  kubectl port-forward -n $NAMESPACE svc/cosmos-service 8080:80"
    fi
}

# Main execution
main() {
    print_info "Starting NVIDIA Cosmos deployment..."
    
    check_prerequisites
    create_namespace
    create_hf_credentials
    create_configmap
    create_pvcs
    deploy_cosmos
    create_service
    create_hpa
    create_pdb
    wait_for_deployment
    get_service_endpoint
    
    print_info "NVIDIA Cosmos deployment completed!"
    echo ""
    print_info "Useful commands:"
    echo "  # Check deployment status"
    echo "  kubectl get all -n $NAMESPACE"
    echo ""
    echo "  # View logs"
    echo "  kubectl logs -f deployment/cosmos-inference -n $NAMESPACE"
    echo ""
    echo "  # View container startup logs"
    echo "  kubectl logs deployment/cosmos-inference -n $NAMESPACE --tail=100"
    echo ""
    echo "  # Check ephemeral storage usage"
    echo "  kubectl exec -it \$(kubectl get pod -n $NAMESPACE -l app=cosmos -o jsonpath='{.items[0].metadata.name}') -n $NAMESPACE -- df -h"
    echo ""
    echo "  # Scale deployment"
    echo "  kubectl scale deployment/cosmos-inference --replicas=3 -n $NAMESPACE"
    echo ""
    echo "  # Port forward for local access"
    echo "  kubectl port-forward -n $NAMESPACE svc/cosmos-service 8080:80"
}

# Run main function
main "$@"
