# Enable required APIs
resource "google_project_service" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"
  
  # Don't disable the service on destroy to avoid dependency issues
  disable_on_destroy = false
}

resource "google_project_service" "container" {
  project = var.project_id
  service = "container.googleapis.com"
  
  # Don't disable the service on destroy to avoid dependency issues
  disable_on_destroy = false
}

# Create VPC
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  project                 = var.project_id
  
  depends_on = [
    google_project_service.compute
  ]
}

# Create Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_range
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id
  
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_range
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_range
  }
  
  private_ip_google_access = true
}

# Firewall rule for internal communication
resource "google_compute_firewall" "internal" {
  name    = "${var.vpc_name}-allow-internal"
  network = google_compute_network.vpc.name
  project = var.project_id
  
  allow {
    protocol = "tcp"
  }
  
  allow {
    protocol = "udp"
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [
    var.subnet_range,
    var.pods_range,
    var.services_range
  ]
}

# Firewall rule for SSH
resource "google_compute_firewall" "ssh" {
  name    = "${var.vpc_name}-allow-ssh"
  network = google_compute_network.vpc.name
  project = var.project_id
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["0.0.0.0/0"]
}

# GKE Cluster with default node pool
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone
  project  = var.project_id
  
  # Disable deletion protection to allow cluster deletion
  deletion_protection = false
  
  # Configure the default node pool
  initial_node_count = 1
  
  node_config {
    machine_type = "e2-standard-4"
    disk_size_gb = 50
    
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    metadata = {
      disable-legacy-endpoints = "true"
    }
    
    # Note: GKE automatically adds the nvidia.com/gpu taint when GPUs are attached
    # No need to manually specify the taint to avoid duplicate taint errors
  }
  
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
  
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  addons_config {
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }
  
  depends_on = [
    google_project_service.container
  ]
}

# GPU Node Pool
resource "google_container_node_pool" "gpu" {
  name       = "gpu-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  project    = var.project_id
  node_count = var.num_nodes
  
  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }
  
  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size
    disk_type    = "pd-balanced"
    
    guest_accelerator {
      type  = var.gpu_type
      count = var.gpu_count
      gpu_driver_installation_config {
        gpu_driver_version = "LATEST"
      }
    }
    
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
  
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
