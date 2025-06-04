# NVIDIA Cosmos on GKE with GPU

This repository contains scripts to deploy NVIDIA Cosmos on Google Kubernetes Engine (GKE) with GPU support for inference workloads. This deployment uses the Vertex AI Model Garden version of Cosmos from Google Artifact Registry.

## Prerequisites

1. **Google Cloud Account** with billing enabled
2. **gcloud CLI** installed and configured
3. **kubectl** installed
4. **Sufficient quota** for GPU instances in your chosen region
5. **HuggingFace Account** with access token for downloading models

## Scripts Overview

- **`create-gke-cluster.sh`** - Creates a GKE cluster with GPU node pool
- **`verify-gpu-drivers.sh`** - Verifies NVIDIA GPU drivers installation
- **`deploy-cosmos.sh`** - Deploys NVIDIA Cosmos for inference
- **`undeploy-cosmos.sh`** - Removes Cosmos deployment (keeps cluster)
- **`cleanup-cluster.sh`** - Removes all resources including the cluster

## Quick Start

### 1. Set Environment Variables

```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_REGION="us-central1"
export GCP_ZONE="us-central1-a"
export CLUSTER_NAME="cosmos-gpu-cluster"
export GPU_TYPE="nvidia-a100-80gb"
export MACHINE_TYPE="a2-ultragpu-1g"  # Required for A100 80GB GPUs
export HF_TOKEN="your-huggingface-token"  # Required for model downloads

# Optional: VPC Configuration (defaults will be used if not set)
export VPC_NAME="cosmos-vpc"
export SUBNET_NAME="cosmos-subnet"
export SUBNET_RANGE="10.0.0.0/24"
export PODS_RANGE="10.1.0.0/16"
export SERVICES_RANGE="10.2.0.0/16"
```

**Note:** You need a HuggingFace account and access token. Get one at https://huggingface.co/settings/tokens

### 2. Create GKE Cluster

```bash
chmod +x create-gke-cluster.sh
./create-gke-cluster.sh
```

This script will:
- Enable required GCP APIs
- Create a custom VPC network with subnet
- Configure firewall rules for internal communication and SSH
- Create a GKE cluster with autoscaling
- Add a GPU node pool with NVIDIA A100 GPUs
- Install NVIDIA GPU drivers

### 3. Verify GPU Setup

```bash
chmod +x verify-gpu-drivers.sh
./verify-gpu-drivers.sh
```

This confirms GPU drivers are installed and working properly.

### 4. Deploy NVIDIA Cosmos

```bash
chmod +x deploy-cosmos.sh
./deploy-cosmos.sh
```

This will:
- Create a dedicated namespace
- Set up HuggingFace authentication
- Download Cosmos model from HuggingFace (on first deployment)
- Deploy Cosmos using Vertex AI's optimized container
- Configure GPU support with proper resource allocation
- Set up autoscaling (HPA)
- Create a LoadBalancer service

**Note:** The deployment uses:
- **HuggingFace** for model downloads (`nvidia/Cosmos-1.0-Diffusion-7B-Text2World`). Update the script for a different model.
- **Vertex AI container** (`us-docker.pkg.dev/vertex-ai/vertex-vision-model-garden-dockers/pytorch-cosmos:20250314`) for optimized inference. You may want to verify if there are new versions of the container.
- Model is downloaded once and stored in a persistent volume for reuse

### 5. Access Cosmos

After deployment, get the service endpoint:

```bash
kubectl get svc -n cosmos
```

For local access:
```bash
kubectl port-forward -n cosmos svc/cosmos-service 8080:80
```

### 6. Test the Service Endpoint

Once the service is deployed, get the LoadBalancer IP:

```bash
# Get the external IP address
COSMOS_IP=$(kubectl get svc cosmos-service -n cosmos -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Cosmos service IP: $COSMOS_IP"

# Wait for IP if not ready yet
while [ -z "$COSMOS_IP" ]; do
  echo "Waiting for LoadBalancer IP..."
  sleep 10
  COSMOS_IP=$(kubectl get svc cosmos-service -n cosmos -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
done
```

#### Check Health Status
```bash
# Test the health endpoint
curl http://$COSMOS_IP/health
```

Expected response should indicate the service is healthy.

#### Test Inference Endpoint
The Vertex AI Cosmos container uses a custom API format for text-to-world generation:

```bash
# Send a test inference request
curl -X POST http://$COSMOS_IP/predict \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [
      {
        "text": "A sleek, humanoid robot stands in a vast warehouse filled with neatly stacked cardboard boxes on industrial shelves."
      }
    ],
    "parameters": {
      "negative_prompt": "",
      "guidance": 7.0,
      "num_steps": 30,
      "height": 704,
      "width": 1280,
      "fps": 24,
      "num_video_frames": 121,
      "seed": 42
    }
  }'
```

The response will include:
- `predictions`: Array containing the generated videos
  - `output`: Base64-encoded video data (MP4 format)

To save the generated video:
```bash
# Generate video and save to file
curl -X POST http://$COSMOS_IP/predict \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [{"text": "A futuristic city with flying cars"}],
    "parameters": {
      "guidance": 7.0,
      "num_steps": 30,
      "height": 704,
      "width": 1280,
      "fps": 24,
      "num_video_frames": 121
    }
  }' | jq -r '.predictions[0].output' | base64 -d > generated_video.mp4
```

#### Parameters Explanation
- `text`: The text prompt describing the scene to generate
- `negative_prompt`: (Optional) What to avoid in the generation
- `guidance`: Guidance scale (default: 7.0)
- `num_steps`: Number of denoising steps (default: 30)
- `height`: Video height in pixels (default: 704)
- `width`: Video width in pixels (default: 1280)
- `fps`: Frames per second (default: 24)
- `num_video_frames`: Total number of frames to generate (default: 121)
- `seed`: Random seed for reproducibility (optional)

#### Monitor GPU Usage
While making requests, you can monitor GPU utilization:
```bash
# Get the pod name
POD_NAME=$(kubectl get pods -n cosmos -l app=cosmos -o jsonpath='{.items[0].metadata.name}')

# Check GPU usage
kubectl exec -it $POD_NAME -n cosmos -- nvidia-smi

# Watch GPU usage in real-time
kubectl exec -it $POD_NAME -n cosmos -- watch -n 1 nvidia-smi
```

#### View Logs
To troubleshoot or monitor the service:
```bash
# View application logs
kubectl logs -f deployment/cosmos-inference -n cosmos

# View specific container logs if there are issues
kubectl logs -f deployment/cosmos-inference -c cosmos -n cosmos

```

#### Full Testing Script
Here's a complete script to test all endpoints:
```bash
#!/bin/bash
# Get the service IP
COSMOS_IP=$(kubectl get svc cosmos-service -n cosmos -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Wait for IP if needed
while [ -z "$COSMOS_IP" ]; do
  echo "Waiting for LoadBalancer IP..."
  sleep 10
  COSMOS_IP=$(kubectl get svc cosmos-service -n cosmos -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
done

echo "Testing Cosmos service at: $COSMOS_IP"

# Test health
echo -e "\n1. Testing health endpoint:"
curl http://$COSMOS_IP/health

# Test inference
echo -e "\n\n2. Testing inference endpoint (this will take several minutes):"
curl -X POST http://$COSMOS_IP/predict \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [
      {
        "text": "A beautiful sunset over mountains"
      }
    ],
    "parameters": {
      "guidance": 7.0,
      "num_steps": 30,
      "height": 704,
      "width": 1280,
      "fps": 24,
      "num_video_frames": 121,
      "seed": 42
    }
  }' | jq -r '.predictions[0].output' | base64 -d > test_video.mp4

echo -e "\nVideo saved as test_video.mp4"
```

## GPU Configuration Options

### Available GPU Types
- `nvidia-a100-80gb` - High performance GPU with 80GB memory (default, requires a2-ultragpu machine types)
- `nvidia-tesla-a100` - A100 with 40GB memory (requires a2-highgpu machine types)
- `nvidia-h100-80gb` - Latest generation GPU with 80GB memory (requires a3-highgpu machine types)
- `nvidia-l4` - High-performance Ada Lovelace GPU for inference (requires g2-standard machine types)

### Modify GPU Configuration

You can use different GPU and machine types for higher performance or lower cost. To change them, edit environment variables before running scripts. For example:
```bash
export GPU_TYPE="nvidia-h100-80gb"
export MACHINE_TYPE="a3-highgpu-8g"  # Adjust based on GPU type
export GPU_COUNT="8"  # GPUs per node
export NUM_NODES="1"  # Number of GPU nodes
```

**Note:** 
- H100 GPUs require a3-highgpu machine types (a3-highgpu-2g provides 2 H100 80GB GPUs)
- A100 80GB GPUs require a2-ultragpu machine types (a2-ultragpu-1g provides 1 A100 80GB GPU)
- A100 40GB GPUs require a2-highgpu machine types (a2-highgpu-1g provides 1 A100 40GB GPU)
- L4 GPUs require g2-standard machine types
- Other GPU types may use n1-standard machine types

### Configure Cosmos Model

The default model is Cosmos-1.0-Diffusion-7B-Text2World from HuggingFace:
```bash
# Default model (if not specified)
export HF_MODEL_ID="nvidia/Cosmos-1.0-Diffusion-7B-Text2World"

# Model path in container
export MODEL_PATH="/models/Cosmos-1.0-Diffusion-7B-Text2World"
```

You can also specify a different container image:
```bash
export COSMOS_IMAGE="us-docker.pkg.dev/vertex-ai/vertex-vision-model-garden-dockers/pytorch-cosmos:20250314"
```

**Note:** The deployment uses Vertex AI's optimized Cosmos container which includes:
- Built-in inference server with OpenAI-compatible API
- GPU optimization for inference
- Automatic model loading from the mounted volume

## Resource Management

### Scaling
```bash
# Manual scaling
kubectl scale deployment/cosmos-inference --replicas=3 -n cosmos

# View HPA status
kubectl get hpa -n cosmos
```

### Monitoring
```bash
# View GPU utilization
kubectl exec -it <pod-name> -n cosmos -- nvidia-smi

# View logs
kubectl logs -f deployment/cosmos-inference -n cosmos
```

## Cost Optimization Tips

1. **Use Preemptible VMs** for non-critical workloads
2. **Enable cluster autoscaling** to scale down during low usage
3. **Use L4 GPUs** for optimal inference performance
4. **Set appropriate resource limits** to avoid over-provisioning

## Cleanup

### Remove Cosmos Deployment Only

To remove just the Cosmos deployment while keeping the cluster:

```bash
chmod +x undeploy-cosmos.sh
./undeploy-cosmos.sh
```

This will:
- Delete all Cosmos resources (deployment, service, HPA, etc.)
- Optionally delete the namespace
- Keep the GKE cluster and GPU nodes running

### Remove Everything

To remove all resources including the cluster:

```bash
chmod +x cleanup-cluster.sh
./cleanup-cluster.sh
```

This will delete:
- The GKE cluster
- All deployed workloads
- Associated persistent volumes
- VPC network and subnet
- Firewall rules

## Troubleshooting

### GPU Not Detected
```bash
# Check node labels
kubectl get nodes --show-labels | grep gpu

# Check GPU driver pods
kubectl get pods -n kube-system -l k8s-app=nvidia-driver-installer
```

### Pod Stuck in Pending
```bash
# Check pod events
kubectl describe pod <pod-name> -n cosmos

# Check node resources
kubectl describe nodes
```

### High Latency
- Ensure pods are scheduled on GPU nodes
- Check GPU utilization with `nvidia-smi`
- Consider increasing replicas or GPU count

## Security Considerations

1. **Enable Workload Identity** for secure GCP service access
2. **Use Private GKE clusters** for production
3. **Configure Network Policies** to restrict traffic
4. **Enable Binary Authorization** for image verification

## Additional Resources

- [GKE GPU Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/gpus)
- [NVIDIA Cosmos Documentation](https://docs.nvidia.com/cosmos/)
- [Kubernetes GPU Scheduling](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)

## License

These scripts are provided as-is for deploying NVIDIA Cosmos on GKE.
