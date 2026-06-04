terraform {
  required_providers {
    k3d = {
      source  = "pvotal-tech/k3d"
      version = "~> 0.0.7"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "k3d" {}

# k3d writes the cluster context to ~/.kube/config when the cluster is created.
# Resources in cluster.tf must be applied before kubernetes/helm resources.
provider "kubernetes" {
  config_path    = pathexpand("~/.kube/config")
  config_context = "k3d-surf-cluster"
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand("~/.kube/config")
    config_context = "k3d-surf-cluster"
  }
}
# comment to test push Actions trigger