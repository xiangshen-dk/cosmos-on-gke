variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
}

variable "zone" {
  description = "GCP Zone"
  type        = string
}

variable "cluster_name" {
  description = "GKE Cluster Name"
  type        = string
}

variable "vpc_name" {
  description = "VPC Network Name"
  type        = string
}

variable "subnet_name" {
  description = "Subnet Name"
  type        = string
}

variable "subnet_range" {
  description = "Subnet IP Range"
  type        = string
}

variable "pods_range" {
  description = "Pods IP Range"
  type        = string
}

variable "services_range" {
  description = "Services IP Range"
  type        = string
}

variable "gpu_type" {
  description = "GPU Type"
  type        = string
}

variable "gpu_count" {
  description = "Number of GPUs per node"
  type        = number
}

variable "machine_type" {
  description = "Machine type for GPU nodes"
  type        = string
}

variable "num_nodes" {
  description = "Number of GPU nodes"
  type        = number
}

variable "min_nodes" {
  description = "Minimum number of GPU nodes"
  type        = number
}

variable "max_nodes" {
  description = "Maximum number of GPU nodes"
  type        = number
}

variable "disk_size" {
  description = "Disk size in GB for GPU nodes"
  type        = number
}
