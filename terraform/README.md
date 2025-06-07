# GKE Infrastructure for Cosmos - Terraform Deployment

This Terraform configuration creates the Google Kubernetes Engine (GKE) infrastructure required for running NVIDIA Cosmos. The actual Cosmos application deployment is now handled separately using Kubernetes manifests.

## Architecture

The deployment creates:
- VPC network with custom subnets
- GKE cluster with GPU-enabled node pools
- Firewall rules for cluster communication
- Workload Identity configuration

## Prerequisites

1. **Terraform** >= 1.0
2. **Google Cloud SDK** (gcloud CLI)
3. **kubectl**
4. **GCP Project** with billing enabled
5. **Sufficient GCP quota** for GPU instances

## Quick Start

### 1. Clone and Navigate

```bash
cd terraform/environments/prod
```

### 2. Configure Variables

Copy the example variables file and edit it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
- `project_id`: Your GCP project ID
- Other variables can be left as defaults or customized

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

This will create:
- VPC network with custom subnets
- GKE cluster with autoscaling
- GPU node pools (default: NVIDIA A100 80GB)

### 4. Deploy Cosmos Application

After the infrastructure is created, deploy the Cosmos application using the Kubernetes manifests:

```bash
cd ../../../kubernetes
./deploy-cosmos.sh \
  -t YOUR_HF_TOKEN \
  -c cosmos-gpu-cluster \
  -z us-central1-a \
  -p your-project-id
```

See [kubernetes/README.md](../../../kubernetes/README.md) for detailed deployment instructions.

## Configuration Options

### GPU Types

The default configuration uses A100 80GB GPUs. To change:

| GPU Type | Machine Type | Variable Updates |
|----------|--------------|------------------|
| A100 80GB | a2-ultragpu-1g | `gpu_type = "nvidia-a100-80gb"` |
| A100 40GB | a2-highgpu-1g | `gpu_type = "nvidia-tesla-a100"` |
| H100 80GB | a3-highgpu-2g | `gpu_type = "nvidia-h100-80gb"` |
| L4 | g2-standard-4 | `gpu_type = "nvidia-l4"` |

### Node Pool Configuration

- `num_nodes`: Initial number of GPU nodes (default: 2)
- `min_nodes`: Minimum nodes for autoscaling (default: 1)
- `max_nodes`: Maximum nodes for autoscaling (default: 4)
- `disk_size`: Disk size per node in GB (default: 400)

### Network Configuration

- `subnet_range`: Primary subnet CIDR (default: 10.0.0.0/24)
- `pods_range`: Secondary range for pods (default: 10.1.0.0/16)
- `services_range`: Secondary range for services (default: 10.2.0.0/16)

## Outputs

After deployment, you can get cluster information:

```bash
# Get cluster name
terraform output cluster_name

# Get cluster endpoint (sensitive)
terraform output cluster_endpoint
```

## Monitoring Infrastructure

### Check Cluster Status

```bash
gcloud container clusters describe cosmos-gpu-cluster \
  --zone us-central1-a \
  --project your-project-id
```

### View Node Pool Status

```bash
gcloud container node-pools describe gpu-pool \
  --cluster cosmos-gpu-cluster \
  --zone us-central1-a \
  --project your-project-id
```

### Check GPU Nodes

```bash
kubectl get nodes -l cloud.google.com/gke-accelerator
```

## Cleanup

To destroy the infrastructure:

```bash
# First, ensure Cosmos application is removed
kubectl delete -f ../../../kubernetes/cosmos/

# Then destroy the infrastructure
terraform destroy
```

**Warning**: This will delete all resources including any data stored in the cluster.

## Cost Optimization

1. **Use Preemptible VMs**: Modify the node pool configuration to use preemptible instances
2. **Enable cluster autoscaling**: Already configured by default
3. **Scale down when not in use**: 
   ```bash
   terraform apply -var="num_nodes=0"
   ```
4. **Use appropriate GPU types**: L4 GPUs are more cost-effective for lighter workloads

## Module Structure

```
terraform/
├── environments/
│   └── prod/
│       ├── main.tf                 # Main configuration
│       ├── variables.tf            # Variable definitions
│       ├── terraform.tfvars.example # Example variables
│       └── backend.tf              # State backend configuration
└── modules/
    └── gke/
        ├── main.tf                 # GKE resources
        ├── variables.tf            # Module inputs
        └── outputs.tf              # Module outputs
```

## Security Considerations

1. **Network Security**: VPC with private subnets for pods/services
2. **Workload Identity**: Enabled for secure GCP service access
3. **Node Security**: Auto-upgrade and auto-repair enabled
4. **Firewall Rules**: Restrictive rules for cluster communication

## Troubleshooting

### Quota Issues

Check your GPU quota:
```bash
gcloud compute project-info describe --project=your-project-id
```

### Node Pool Creation Fails

Verify GPU availability in your zone:
```bash
gcloud compute accelerator-types list --filter="zone:us-central1-a"
```

### API Not Enabled

Enable required APIs:
```bash
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
```

## Support

For issues related to:
- **Terraform Configuration**: Check the module documentation
- **GKE**: See [GKE GPU Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/gpus)
- **Cosmos Deployment**: See [kubernetes/README.md](../../../kubernetes/README.md)
