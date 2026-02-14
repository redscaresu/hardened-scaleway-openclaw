terraform {
  required_version = ">= 1.5"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend configured by bootstrap/init-remote-state.sh
  # See backend-config.tf (auto-generated)
}

provider "scaleway" {
  zone   = var.zone
  region = var.region
}
