# Bootstrap uses LOCAL state on purpose: the remote state bucket does not exist
# until this stack creates it (chicken-and-egg). After the first apply you can
# migrate it - see docs/devops/setup-guide.md, step 3.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.40"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.40"
    }
  }
}
