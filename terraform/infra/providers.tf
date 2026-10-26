terraform {
  required_version = "~> 1.17"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.4" }
    helm       = { source = "hashicorp/helm",       version = "~> 3.3" }
  }
}

# Desktop uses ~/.kube/config; Atlantis runs in-cluster.
provider "kubernetes" {
  config_path = var.kubeconfig_path
  config_context = var.kubeconfig_context
}
provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
    config_context = var.kubeconfig_context
  }
}
variable "kubeconfig_path" {
  type = string
  default = "~/.kube/config"
  description = "In-cluster (Atlantis): override to empty"
}
variable "kubeconfig_context" {
  type    = string
  default = ""
}
