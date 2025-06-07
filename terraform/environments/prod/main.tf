terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# Configure the Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# GKE Module
module "gke" {
  source = "../../modules/gke"
  
  project_id     = var.project_id
  region         = var.region
  zone           = var.zone
  cluster_name   = var.cluster_name
  
  # VPC Configuration
  vpc_name       = var.vpc_name
  subnet_name    = var.subnet_name
  subnet_range   = var.subnet_range
  pods_range     = var.pods_range
  services_range = var.services_range
  
  # GPU Configuration
  gpu_type       = var.gpu_type
  gpu_count      = var.gpu_count
  machine_type   = var.machine_type
  num_nodes      = var.num_nodes
  min_nodes      = var.min_nodes
  max_nodes      = var.max_nodes
  disk_size      = var.disk_size
}

# Outputs
output "cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.endpoint
  sensitive   = true
}

# Note: Cosmos deployment outputs are now available through kubectl commands
# After deploying with kubernetes/deploy-cosmos.sh, use:
# kubectl get svc cosmos-service -n cosmos -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
