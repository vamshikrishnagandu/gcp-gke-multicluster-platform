# -----------------------------------------------------------------------------
# GKE module: ONE regional, private, hardened Standard cluster + node pool.
# Called once per region from envs/prod (for_each).
# -----------------------------------------------------------------------------

# Least-privilege node identity (the default Compute SA has roles/editor!).
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = "GKE nodes - ${var.name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/autoscaling.metricsWriter",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  provider = google

  project  = var.project_id
  name     = var.name
  location = var.region # region => regional (HA) control plane

  network         = var.network
  subnetwork      = var.subnetwork
  networking_mode = "VPC_NATIVE" # pods get VPC IPs -> container-native LB via NEGs

  # Dataplane V2 (eBPF/Cilium): built-in NetworkPolicy enforcement + network logging
  datapath_provider = "ADVANCED_DATAPATH"

  # A cluster must be created with a node pool; we delete it and manage our own.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection
  resource_labels     = var.labels

  release_channel {
    channel = var.release_channel
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true  # nodes have no public IP
    enable_private_endpoint = false # keep public endpoint but lock it via authorized networks
    master_ipv4_cidr_block  = var.master_cidr

    master_global_access_config {
      enabled = true
    }
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # DNS-based control-plane endpoint: reachable from anywhere but every call is
  # authorised by IAM -> laptops and GitHub runners need no IP allow-listing.
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Register in the project fleet (needed for multi-cluster Gateway / Services).
  fleet {
    project = var.project_id
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    gke_backup_agent_config {
      enabled = true
    }
  }

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
      "CONTROLLER_MANAGER",
      "SCHEDULER",
    ]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "STORAGE", "HPA", "POD", "DEPLOYMENT"]

    managed_prometheus {
      enabled = true
    }
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  enable_shielded_nodes       = true
  enable_intranode_visibility = true # pod-to-pod traffic on the same node shows up in VPC flow logs

  # GKE usage metering -> BigQuery: CPU/memory requested AND consumed per namespace.
  # Feeds the Grafana "resource utilisation" panel straight from BigQuery.
  dynamic "resource_usage_export_config" {
    for_each = var.usage_export_dataset != "" ? [1] : []
    content {
      enable_network_egress_metering       = false
      enable_resource_consumption_metering = true
      bigquery_destination {
        dataset_id = var.usage_export_dataset
      }
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = "2025-01-04T03:00:00Z"
      end_time   = "2025-01-04T09:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]

    precondition {
      condition     = var.binauthz_policy_id != ""
      error_message = "The Binary Authorization policy must exist before creating a GKE cluster."
    }
  }
}

resource "google_container_node_pool" "primary" {
  project        = var.project_id
  name           = "primary"
  location       = var.region
  cluster        = google_container_cluster.this.name
  node_locations = length(var.node_locations) > 0 ? var.node_locations : null

  autoscaling {
    total_min_node_count = var.min_nodes
    total_max_node_count = var.max_nodes
    location_policy      = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.machine_type
    spot            = var.spot
    image_type      = "COS_CONTAINERD"
    disk_type       = "pd-balanced"
    disk_size_gb    = 50
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"] # IAM decides, not scopes
    labels          = var.labels

    workload_metadata_config {
      mode = "GKE_METADATA" # pods see the WI metadata server, never the node SA
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  depends_on = [google_project_iam_member.nodes]
}

# Backup for GKE: GKE manages etcd itself (no direct etcd access), so this is the
# supported way to back up cluster state (manifests + secrets + PV data).
resource "google_gke_backup_backup_plan" "daily" {
  project  = var.project_id
  name     = "${var.name}-daily"
  cluster  = google_container_cluster.this.id
  location = var.region

  retention_policy {
    backup_retain_days = var.backup_retain_days
  }

  backup_schedule {
    cron_schedule = "0 2 * * *"
  }

  backup_config {
    include_volume_data = true
    include_secrets     = true

    selected_namespaces {
      namespaces = var.backup_namespaces
    }
  }
}
