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
}

module "network" {
  source     = "../../modules/network"
  project_id = var.project_id
  subnets = { for k, r in var.regions : k => {
    region        = r.region
    nodes_cidr    = r.nodes_cidr
    pods_cidr     = r.pods_cidr
    services_cidr = r.services_cidr
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
}

module "data" {
  source                 = "../../modules/data"
  project_id             = var.project_id
  network_id             = module.network.network_id
  primary_region         = local.primary_region
  secondary_region       = local.secondary_region
  enable_sql_replica     = var.enable_sql_replica
  app_names              = var.apps
  app_service_accounts   = module.security.app_service_accounts
  secret_replica_regions = local.all_regions
  deletion_protection    = var.deletion_protection

  depends_on = [module.network] # wait for Private Services Access peering
}

module "observability" {
  source            = "../../modules/observability"
  project_id        = var.project_id
  uptime_host       = var.uptime_host
  alert_email       = var.alert_email
  grafana_principal = var.grafana_principal
}

# Static anycast IP for the multi-cluster Gateway (referenced by charts/gateway).
resource "google_compute_global_address" "gateway" {
  project = var.project_id
  name    = "platform-gateway-ip"
}
