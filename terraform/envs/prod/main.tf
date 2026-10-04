# -----------------------------------------------------------------------------
# PROD environment - composes all modules.
# Dependency order (Terraform works it out from references):
#   network -> gke (x2) -> fleet
#   network -> data
#   security, registry, observability (independent)
# -----------------------------------------------------------------------------

provider "google" {
  project = var.project_id
  region  = local.primary_region
}

locals {
  cluster_keys     = sort(keys(var.regions))
  config_key       = local.cluster_keys[0]
  primary_region   = var.regions[local.cluster_keys[0]].region
  secondary_region = var.regions[local.cluster_keys[1]].region
  all_regions      = [for k in local.cluster_keys : var.regions[k].region]

  # nip.io resolves <a>-<b>-<c>-<d>.nip.io to a.b.c.d, so a Google-managed cert works without owning a domain.
  gateway_hostname = var.domain != "" ? var.domain : "${replace(google_compute_global_address.gateway.address, ".", "-")}.nip.io"
}

module "network" {
  source     = "../../modules/network"
  project_id = var.project_id
  subnets = { for k, r in var.regions : k => {
    region        = r.region
    nodes_cidr    = r.nodes_cidr
    pods_cidr     = r.pods_cidr
    services_cidr = r.services_cidr
    ops_cidr      = r.ops_cidr
    proxy_cidr    = r.proxy_cidr
  } }
}

module "registry" {
  source     = "../../modules/registry"
  project_id = var.project_id
  location   = "us"
  labels     = var.labels
}

module "security" {
  source                    = "../../modules/security"
  project_id                = var.project_id
  apps                      = var.apps
  secret_replica_regions    = local.all_regions
  ci_apps_sa                = var.ci_apps_sa
  binauthz_enforcement_mode = var.binauthz_enforcement_mode
}

module "gke" {
  source   = "../../modules/gke"
  for_each = var.regions

  project_id           = var.project_id
  name                 = "gke-${each.key}"
  region               = each.value.region
  network              = module.network.network_self_link
  subnetwork           = module.network.subnets[each.key].self_link
  master_cidr          = each.value.master_cidr
  machine_type         = var.machine_type
  spot                 = var.spot_nodes
  min_nodes            = var.min_nodes_per_cluster
  max_nodes            = var.max_nodes_per_cluster
  backup_namespaces    = var.apps
  usage_export_dataset = module.observability.usage_dataset
  deletion_protection  = var.deletion_protection
  labels               = var.labels
  binauthz_policy_id   = module.security.binary_authorization_policy_id

}

resource "google_service_account_iam_member" "workload_identity" {
  for_each = toset(var.apps)

  service_account_id = module.security.app_service_account_names[each.key]
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${module.gke[local.config_key].workload_pool}[${each.key}/${each.key}]"
}

module "fleet" {
  source            = "../../modules/fleet"
  project_id        = var.project_id
  config_membership = module.gke[local.config_key].membership
  workload_pool     = module.gke[local.config_key].workload_pool
  memberships = {
    for key, cluster in module.gke : key => {
      id       = cluster.membership_id
      location = cluster.membership_location
    }
  }
}

module "data" {
  source                   = "../../modules/data"
  project_id               = var.project_id
  network_id               = module.network.network_id
  primary_region           = local.primary_region
  secondary_region         = local.secondary_region
  enable_sql_replica       = var.enable_sql_replica
  enable_redis_dr_instance = var.enable_redis_dr_instance
  app_names                = var.apps
  app_service_accounts     = module.security.app_service_accounts
  secret_replica_regions   = local.all_regions
  deletion_protection      = var.deletion_protection

  depends_on = [module.network] # wait for Private Services Access peering
}

module "observability" {
  source            = "../../modules/observability"
  project_id        = var.project_id
  uptime_host       = var.uptime_host != "" ? local.gateway_hostname : ""
  uptime_use_ssl    = true
  alert_email       = var.alert_email
  grafana_principal = var.grafana_principal
}

module "iam" {
  source     = "../../modules/iam"
  project_id = var.project_id
  developers = var.team_members.developers
  operators  = var.team_members.operators
  sres       = var.team_members.sres
}

# Schema/grants Job (charts/app, app1 namespace) uses KSA app1/db-init.
resource "google_service_account_iam_member" "db_init_workload_identity" {
  service_account_id = module.data.db_init_service_account_name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${module.gke[local.config_key].workload_pool}[app1/db-init]"
}

# Static anycast IP for the multi-cluster Gateway (referenced by charts/gateway).
resource "google_compute_global_address" "gateway" {
  project = var.project_id
  name    = "platform-gateway-ip"
}

# Google-managed TLS certificate, attached to the Gateway by name (pre-shared cert).
# The hash in the name lets a hostname change replace the cert without a name clash.
resource "google_compute_managed_ssl_certificate" "gateway" {
  project = var.project_id
  name    = "platform-gw-${substr(sha1(local.gateway_hostname), 0, 8)}"

  managed {
    domains = [local.gateway_hostname]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Optional Cloud DNS zone for a domain you own; delegate its nameservers at your registrar.
resource "google_dns_managed_zone" "public" {
  count = var.dns_zone_domain != "" ? 1 : 0

  project     = var.project_id
  name        = "platform-public"
  dns_name    = "${var.dns_zone_domain}."
  description = "Public zone for the platform Gateway"

  dnssec_config {
    state = "on"
  }
}

resource "google_dns_record_set" "gateway" {
  count = var.dns_zone_domain != "" ? 1 : 0

  project      = var.project_id
  managed_zone = google_dns_managed_zone.public[0].name
  name         = "${local.gateway_hostname}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.gateway.address]
}
