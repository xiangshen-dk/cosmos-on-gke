# GCP Configuration
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

# Cluster Configuration
variable "cluster_name" {
  description = "GKE Cluster Name"
  type        = string
  default     = "cosmos-gpu-cluster"
}

# VPC Configuration
variable "vpc_name" {
  description = "VPC Network Name"
  type        = string
  default     = "cosmos-vpc"
}

variable "subnet_name" {
  description = "Subnet Name"
  type        = string
  default     = "cosmos-subnet"
}

variable "subnet_range" {
  description = "Subnet IP Range"
  type        = string
  default     = "10.0.0.0/24"
}

variable "pods_range" {
  description = "Pods IP Range"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_range" {
  description = "Services IP Range"
  type        = string
  default     = "10.2.0.0/16"
}

# GPU Node Pool Configuration
variable "gpu_type" {
  description = "GPU Type"
  type        = string
  default     = "nvidia-a100-80gb"
}

variable "gpu_count" {
  description = "Number of GPUs per node"
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "Machine type for GPU nodes"
  type        = string
  default     = "a2-ultragpu-1g"
}

variable "num_nodes" {
  description = "Number of GPU nodes"
  type        = number
  default     = 2
}

variable "min_nodes" {
  description = "Minimum number of GPU nodes"
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Maximum number of GPU nodes"
  type        = number
  default     = 4
}

variable "disk_size" {
  description = "Disk size in GB for GPU nodes"
  type        = number
  default     = 400
}
