# -----------------------------------------------------------------------------
# Network module: one GLOBAL custom-mode VPC, one subnet per region.
#   - Secondary ranges for GKE pods/services (VPC-native = required for NEGs)
#   - Cloud NAT per region (private nodes have no public IP but need egress)
#   - VPC Flow Logs + firewall logging (observability + compliance)
#   - Private Services Access peering for Cloud SQL / Memorystore private IPs
# -----------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  project                         = var.project_id
  name                            = var.network_name
  auto_create_subnetworks         = false
  routing_mode                    = "GLOBAL" # routes learned in one region are usable in all
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "subnet" {
  for_each = var.subnets

  project                  = var.project_id
  name                     = "${var.network_name}-${each.key}"
  region                   = each.value.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = each.value.nodes_cidr
  private_ip_google_access = true # reach Google APIs (GCR/AR, logging) without a public IP

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = each.value.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = each.value.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ---------------------------------------------------------------- Cloud NAT
resource "google_compute_router" "router" {
  for_each = var.subnets

  project = var.project_id
  name    = "${var.network_name}-router-${each.key}"
  region  = each.value.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  for_each = var.subnets

  project                            = var.project_id
  name                               = "${var.network_name}-nat-${each.key}"
  router                             = google_compute_router.router[each.key].name
  region                             = each.value.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ---------------------------------------------------------------- Firewall
# Google front ends + health checkers must reach pods directly (container-native LB / NEGs).
resource "google_compute_firewall" "allow_gfe_health_checks" {
  project       = var.project_id
  name          = "${var.network_name}-allow-gfe-hc"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

  allow {
    protocol = "tcp"
    ports    = ["8080"] # app container port
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Cross-cluster traffic (Multi-Cluster Services: app2 in cluster A -> app1 pod in cluster B).
# GKE only auto-creates rules for a cluster's OWN pod range, so without this the
# deny-all below would silently break cross-region service calls.
resource "google_compute_firewall" "allow_internal" {
  project   = var.project_id
  name      = "${var.network_name}-allow-internal"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000
  source_ranges = flatten([
    for s in var.subnets : [s.nodes_cidr, s.pods_cidr]
  ])

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

# Identity-Aware Proxy TCP forwarding range: SSH to nodes only via IAP (no public SSH).
resource "google_compute_firewall" "allow_iap_ssh" {
  project       = var.project_id
  name          = "${var.network_name}-allow-iap-ssh"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Explicit, logged deny-all. GCP's implied deny is NOT logged; this one is.
resource "google_compute_firewall" "deny_all_ingress" {
  project       = var.project_id
  name          = "${var.network_name}-deny-all-ingress"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 65000
  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ---------------------------------------------------------------- Private Services Access
resource "google_compute_global_address" "psa" {
  project       = var.project_id
  name          = "${var.network_name}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = split("/", var.psa_cidr)[0]
  prefix_length = tonumber(split("/", var.psa_cidr)[1])
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
  deletion_policy         = "ABANDON" # avoids "producer services still using this connection" on destroy
}
