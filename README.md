# NVIDIA Cosmos on GKE

This repository contains the infrastructure and deployment configurations for running NVIDIA Cosmos on Google Kubernetes Engine (GKE) with GPU support.

## Project Structure

```
.
├── terraform/              # Infrastructure as Code for GKE
│   ├── environments/      # Environment-specific configurations
│   │   └── prod/         # Production environment
│   ├── modules/          # Reusable Terraform modules
│   │   └── gke/         # GKE cluster module
│   ├── deploy.sh        # Infrastructure deployment script
│   └── destroy.sh       # Infrastructure cleanup script
│
├── kubernetes/            # Kubernetes manifests for Cosmos
│   ├── cosmos/           # Base Kubernetes resources
│   │   ├── 00-namespace.yaml
│   │   ├── 01-secret.yaml
│   │   ├── 02-configmap.yaml
│   │   ├── 03-pvcs.yaml
│   │   ├── 04-deployment.yaml
│   │   ├── 05-service.yaml
│   │   ├── 06-hpa.yaml
│   │   └── 07-pdb.yaml
│   ├── deploy-cosmos.sh  # Application deployment script
│   └── cleanup-cosmos.sh # Application cleanup script
│
└── scripts/              # Alternative deployment method (shell scripts)
    ├── create-gke-cluster.sh    # Create GKE cluster
    ├── deploy-cosmos.sh         # Deploy Cosmos
    ├── cleanup-cluster.sh       # Remove cluster
    └── README.md               # Scripts documentation
```

## Deployment Methods

This repository provides two deployment methods:

### Method 1: Terraform + Kubernetes (Recommended)
- **terraform/**: Infrastructure as Code for creating GKE cluster
- **kubernetes/**: Kubernetes manifests and deployment scripts
- Best for production environments with infrastructure versioning needs

### Method 2: Shell Scripts Only
- **scripts/**: All-in-one shell scripts for both infrastructure and application
- Best for quick testing or development environments
- See [scripts/README.md](scripts/README.md) for detailed instructions

## Deployment Overview

The deployment is separated into two distinct layers:

1. **Infrastructure Layer** (Terraform)
   - Creates GCP resources: VPC, subnets, firewall rules
   - Deploys GKE cluster with GPU-enabled node pools
   - Configures cluster settings and workload identity

2. **Application Layer** (Kubernetes)
   - Deploys NVIDIA Cosmos application
   - Manages secrets, configurations, and storage
   - Handles scaling and availability

## Quick Start

### Prerequisites

- Google Cloud SDK (`gcloud`)
- Terraform >= 1.0
- kubectl
- GCP Project with billing enabled
- HuggingFace token for model access
- Sufficient GPU quota in GCP

### Step 1: Deploy Infrastructure

```bash
# Navigate to Terraform environment
cd terraform/environments/prod

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project details

# Deploy infrastructure
../../deploy.sh
```

### Step 2: Deploy Cosmos Application

```bash
# Navigate to Kubernetes directory
cd ../../../kubernetes

# Deploy Cosmos with your HuggingFace token
./deploy-cosmos.sh \
  -t YOUR_HF_TOKEN \
  -c cosmos-gpu-cluster \
  -z us-central1-a \
  -p your-project-id
```

## Configuration

### Infrastructure Configuration (Terraform)

Key variables in `terraform/environments/prod/terraform.tfvars`:
- `project_id`: Your GCP project ID
- `gpu_type`: GPU type (default: nvidia-a100-80gb)
- `num_nodes`: Number of GPU nodes
- `machine_type`: GCE machine type for nodes

### Application Configuration (Kubernetes)

The deployment script accepts various parameters:
- `-t, --token`: HuggingFace token (required)
- `-g, --gpu-type`: GPU type for node selector (default: nvidia-a100-80gb)
- `-m, --model-id`: Cosmos model to use (default: nvidia/Cosmos-1.0-Diffusion-7B-Text2World)
- `-i, --image`: Container image (default: Vertex AI image)
- `-s, --model-storage`: Storage size for models (default: 150Gi)
- `-d, --cache-storage`: Cache storage size (default: 100Gi)
- `-r, --replicas`: Number of replicas (default: 1)

## GPU Selection

This deployment uses NVIDIA A100 80GB GPUs as the default example configuration. The A100 provides excellent performance for running NVIDIA Cosmos models and is widely available on GCP.

### Alternative GPU Options

While A100 GPUs offer great performance, other GPU types can provide even better performance characteristics, though at a higher cost. For example:

- **NVIDIA H100**: Next-generation GPU with significant performance improvements over A100, especially for large language models and diffusion models. Offers up to 3x performance improvement but at approximately 2-3x the cost.
- **NVIDIA H200**: High-performance GPU with enhanced memory bandwidth and capacity. Provides excellent performance for memory-intensive workloads but comes at a premium price point.
- **NVIDIA L4**: More cost-effective option for lighter workloads or development environments, though with reduced performance compared to A100.

### Configuring GPU Type

To use a different GPU type, update the following:

1. **Terraform Configuration**: Set `gpu_type` in your `terraform.tfvars`:
   ```hcl
   gpu_type = "nvidia-h100-80gb"  # or "nvidia-h200-141gb", "nvidia-l4", etc.
   ```

2. **Kubernetes Deployment**: Use the `-g` flag when deploying:
   ```bash
   ./deploy-cosmos.sh -t YOUR_HF_TOKEN -g nvidia-h100-80gb
   ```

**Note**: Ensure your GCP project has sufficient quota for your chosen GPU type. Premium GPUs like H100 and H200 may have limited availability and require quota increases.

## Monitoring

### Check Infrastructure Status
```bash
# View cluster status, change zone and project id as needed
gcloud container clusters describe cosmos-gpu-cluster \
  --zone us-central1-a --project your-project-id

# Check nodes
kubectl get nodes -l cloud.google.com/gke-accelerator
```

### Check Application Status
```bash
# View pods
kubectl get pods -n cosmos

# Check logs
kubectl logs -f deployment/cosmos-inference -n cosmos

# Get service endpoint
kubectl get svc cosmos-service -n cosmos
```

## Testing

Once the service is deployed, you can test the Cosmos endpoints:

### Get the Service Endpoint

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

### Check Health Status
```bash
# Test the health endpoint
curl http://$COSMOS_IP/health
```

Expected response should indicate the service is healthy.

### Test Inference Endpoint
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

### Parameters Explanation
- `text`: The text prompt describing the scene to generate
- `negative_prompt`: (Optional) What to avoid in the generation
- `guidance`: Guidance scale (default: 7.0)
- `num_steps`: Number of denoising steps (default: 30)
- `height`: Video height in pixels (default: 704)
- `width`: Video width in pixels (default: 1280)
- `fps`: Frames per second (default: 24)
- `num_video_frames`: Total number of frames to generate (default: 121)
- `seed`: Random seed for reproducibility (optional)

### Monitor GPU Usage
While making requests, you can monitor GPU utilization:
```bash
# Get the pod name
POD_NAME=$(kubectl get pods -n cosmos -l app=cosmos -o jsonpath='{.items[0].metadata.name}')

# Check GPU usage
kubectl exec -it $POD_NAME -n cosmos -- nvidia-smi

# Watch GPU usage in real-time
kubectl exec -it $POD_NAME -n cosmos -- watch -n 1 nvidia-smi
```

### View Logs
To troubleshoot or monitor the service:
```bash
# View application logs
kubectl logs -f deployment/cosmos-inference -n cosmos

# View specific container logs if there are issues
kubectl logs -f deployment/cosmos-inference -c cosmos -n cosmos
```

### Full Testing Script
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

## Cleanup

### Remove Application
```bash
# Using the cleanup script (recommended)
cd kubernetes
./cleanup-cosmos.sh -c cosmos-gpu-cluster -z us-central1-a -p your-project-id

# Or manually
kubectl delete -f kubernetes/cosmos/
```

### Destroy Infrastructure
```bash
cd terraform/environments/prod
../../destroy.sh
```

**Note**: The cleanup script preserves PVCs by default. Use `--delete-pvcs` flag to remove them.

## Documentation

- [Terraform Infrastructure Guide](terraform/README.md)
- [Kubernetes Deployment Guide](kubernetes/README.md)
- [NVIDIA Cosmos Documentation](https://docs.nvidia.com/cosmos/)
- [GKE GPU Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/gpus)

## Security Considerations

- HuggingFace tokens are stored as Kubernetes secrets
- Network isolation via VPC and firewall rules
- Workload Identity enabled for secure GCP access
- Node auto-upgrade and auto-repair enabled

## Cost Optimization

- Use preemptible VMs for non-production workloads
- Scale down GPU nodes when not in use
- Consider L4 GPUs for lighter workloads
- Enable cluster autoscaling (configured by default)

## Troubleshooting

See the individual README files:
- [Infrastructure Troubleshooting](terraform/README.md#troubleshooting)
- [Application Troubleshooting](kubernetes/README.md#troubleshooting)

## Contributing

When making changes:
1. Test infrastructure changes in a dev environment first
2. Update documentation as needed
3. Follow the existing naming conventions
4. Keep infrastructure and application concerns separated
