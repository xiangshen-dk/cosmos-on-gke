# Cosmos Kubernetes Deployment

This directory contains the Kubernetes manifests for deploying the Cosmos application to a GKE cluster.

## Directory Structure

```
kubernetes/
├── cosmos/                    # Base Kubernetes manifests
│   ├── 00-namespace.yaml     # Namespace definition
│   ├── 01-secret.yaml        # HuggingFace token secret
│   ├── 02-configmap.yaml     # Application configuration
│   ├── 03-pvcs.yaml          # Persistent Volume Claims
│   ├── 04-deployment.yaml    # Deployment configuration
│   ├── 05-service.yaml       # LoadBalancer service
│   ├── 06-hpa.yaml           # Horizontal Pod Autoscaler
│   ├── 07-pdb.yaml           # Pod Disruption Budget
│   └── kustomization.yaml    # Kustomize configuration
└── deploy-cosmos.sh          # Deployment script
```

## Prerequisites

1. A GKE cluster with GPU nodes (created using Terraform)
2. `kubectl` configured to access the cluster
3. `gcloud` CLI installed and authenticated
4. A valid HuggingFace token

## Deployment Steps

### Option 1: Using the Deployment Script (Recommended)

The easiest way to deploy Cosmos is using the provided deployment script:

```bash
./kubernetes/deploy-cosmos.sh \
  -t YOUR_HF_TOKEN \
  -c cosmos-gpu-cluster \
  -z us-central1-a \
  -p your-project-id
```

#### Script Options

- `-t, --token`: HuggingFace token (required)
- `-c, --cluster`: GKE cluster name (required)
- `-z, --zone`: GKE cluster zone (required)
- `-p, --project`: GCP project ID (required)
- `-g, --gpu-type`: GPU type (default: nvidia-a100-80gb)
- `-m, --model-id`: Model ID (default: nvidia/Cosmos-1.0-Diffusion-7B-Text2World)
- `-i, --image`: Container image (default: us-docker.pkg.dev/vertex-ai/vertex-vision-model-garden-dockers/pytorch-cosmos:20250314)
- `-s, --model-storage`: Model storage size (default: 150Gi)
- `-d, --cache-storage`: Cache storage size (default: 100Gi)
- `-r, --replicas`: Number of replicas (default: 1)

### Option 2: Manual Deployment

1. **Get cluster credentials:**
   ```bash
   gcloud container clusters get-credentials cosmos-gpu-cluster \
     --zone us-central1-a \
     --project your-project-id
   ```

2. **Create the HuggingFace token secret:**
   ```bash
   # First, encode your token
   echo -n "your-hf-token" | base64
   
   # Then update the secret file with the encoded token
   sed -i 's/REPLACE_WITH_BASE64_ENCODED_TOKEN/YOUR_BASE64_TOKEN/' kubernetes/cosmos/01-secret.yaml
   ```

3. **Apply the manifests:**
   ```bash
   # Apply individual YAML files (excluding kustomization.yaml)
   kubectl apply -f kubernetes/cosmos/00-namespace.yaml
   kubectl apply -f kubernetes/cosmos/01-secret.yaml
   kubectl apply -f kubernetes/cosmos/02-configmap.yaml
   kubectl apply -f kubernetes/cosmos/03-pvcs.yaml
   kubectl apply -f kubernetes/cosmos/04-deployment.yaml
   kubectl apply -f kubernetes/cosmos/05-service.yaml
   kubectl apply -f kubernetes/cosmos/06-hpa.yaml
   kubectl apply -f kubernetes/cosmos/07-pdb.yaml
   ```

4. **Wait for deployment to be ready:**
   ```bash
   kubectl wait --for=condition=available --timeout=2400s deployment/cosmos-inference -n cosmos
   ```

5. **Get the service external IP:**
   ```bash
   kubectl get svc cosmos-service -n cosmos
   ```

## Customization

### Using Kustomize (Optional)

The manifests include a `kustomization.yaml` file for easy customization. To use it:

```bash
# Apply with kustomize (requires kubectl 1.14+)
kubectl apply -k kubernetes/cosmos/

# Or use the kustomize binary directly
kustomize build kubernetes/cosmos/ | kubectl apply -f -
```

**Note**: The deployment script does not use kustomize by default. It applies the YAML files directly after customizing them based on the provided parameters.

### Environment-specific Overlays

For different environments (dev, staging, prod), create overlay directories:

```
kubernetes/
├── cosmos/          # Base manifests
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

Example overlay `kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../cosmos

patchesStrategicMerge:
  - deployment-patch.yaml

configMapGenerator:
  - name: cosmos-config
    behavior: merge
    files:
      - inference.yaml
```

## Monitoring and Management

### Check deployment status:
```bash
kubectl get pods -n cosmos
kubectl get deployment cosmos-inference -n cosmos
```

### View logs:
```bash
kubectl logs -f deployment/cosmos-inference -n cosmos
```

### Scale deployment:
```bash
kubectl scale deployment/cosmos-inference --replicas=3 -n cosmos
```

### Check HPA status:
```bash
kubectl get hpa cosmos-hpa -n cosmos
```

### Update deployment:
```bash
# Edit deployment
kubectl edit deployment cosmos-inference -n cosmos

# Or apply updated manifest
kubectl apply -f kubernetes/cosmos/04-deployment.yaml
```

## Troubleshooting

### Pod not starting:
1. Check pod status: `kubectl describe pod <pod-name> -n cosmos`
2. Check events: `kubectl get events -n cosmos --sort-by='.lastTimestamp'`
3. Verify GPU nodes are available: `kubectl get nodes -l cloud.google.com/gke-accelerator`

### Model download issues:
1. Check if HuggingFace token is valid
2. Verify sufficient storage in PVCs
3. Check pod logs for download progress

### Service not accessible:
1. Verify LoadBalancer has external IP: `kubectl get svc cosmos-service -n cosmos`
2. Check firewall rules in GCP
3. Ensure pods are running and ready

## Cleanup

### Using the Cleanup Script (Recommended)

The easiest way to remove Cosmos is using the provided cleanup script:

```bash
# Basic cleanup (preserves PVCs)
./kubernetes/cleanup-cosmos.sh \
  -c cosmos-gpu-cluster \
  -z us-central1-a \
  -p your-project-id

# Force cleanup including PVCs (data will be lost!)
./kubernetes/cleanup-cosmos.sh \
  -c cosmos-gpu-cluster \
  -z us-central1-a \
  -p your-project-id \
  -f --delete-pvcs
```

#### Cleanup Script Options

- `-c, --cluster`: GKE cluster name (required)
- `-z, --zone`: GKE cluster zone (required)
- `-p, --project`: GCP project ID (required)
- `-f, --force`: Skip confirmation prompts
- `--delete-pvcs`: Also delete PersistentVolumeClaims (data will be lost!)

### Manual Cleanup

To manually remove the Cosmos deployment:
```bash
# Delete all resources except PVCs
kubectl delete deployment,service,hpa,pdb,configmap,secret -n cosmos -l app.kubernetes.io/name=cosmos

# Delete PVCs (optional - this will delete data)
kubectl delete pvc -n cosmos -l app.kubernetes.io/name=cosmos

# Delete namespace
kubectl delete namespace cosmos
```

### Cleanup Considerations

1. **PersistentVolumeClaims**: By default, PVCs are preserved to prevent data loss
2. **LoadBalancer**: The service deletion will release the external IP
3. **PersistentVolumes**: May remain in "Released" state after PVC deletion
4. **Namespace**: Only deleted if empty or with force flag

To check for orphaned resources after cleanup:
```bash
# Check for orphaned PVs
kubectl get pv | grep cosmos

# Check if namespace still exists
kubectl get namespace cosmos
