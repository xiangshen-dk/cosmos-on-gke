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

## Architecture Overview

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

## Monitoring

### Check Infrastructure Status
```bash
# View cluster status
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
