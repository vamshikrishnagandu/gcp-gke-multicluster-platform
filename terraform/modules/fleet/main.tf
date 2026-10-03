# -----------------------------------------------------------------------------
# Fleet module: turns N independent clusters into ONE multi-cluster platform.
#   - Multi-Cluster Services (MCS): ServiceExport/ServiceImport across clusters
#   - Multi-Cluster Ingress/Gateway: ONE global external Application LB whose
#     backends are NEGs in every cluster. "config cluster" holds the Gateway.
# -----------------------------------------------------------------------------

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_gke_hub_feature" "mcs" {
  project  = var.project_id
  name     = "multiclusterservicediscovery"
  location = "global"
}

resource "google_gke_hub_feature" "mci" {
  project  = var.project_id
  name     = "multiclusteringress"
  location = "global"

  spec {
    multiclusteringress {
      config_membership = var.config_membership
    }
  }

  depends_on = [google_gke_hub_feature.mcs]
}

# The MCS importer (runs in each cluster as a KSA) needs to read the VPC.
resource "google_project_iam_member" "mcs_importer" {
  project = var.project_id
  role    = "roles/compute.networkViewer"
  member  = "serviceAccount:${var.project_id}.svc.id.goog[gke-mcs/gke-mcs-importer]"

  depends_on = [google_gke_hub_feature.mcs]
}

# Google-managed MCI controller creates LBs/NEGs in our project on our behalf.
resource "google_project_iam_member" "mci_controller" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-multiclusteringress.iam.gserviceaccount.com"

  depends_on = [google_gke_hub_feature.mci]
}
