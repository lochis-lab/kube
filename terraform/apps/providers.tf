terraform {
  required_version = "~> 1.17"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.4" }
  }
  backend "kubernetes" {
    namespace     = "ops"
    secret_suffix = "kube-apps"
    labels        = { managed_by = "terraform", repo = "kube" }
  }
}

# Desktop: TF_VAR_kubeconfig_path=~/.kube/config; Atlantis: in-cluster (empty default)
provider "kubernetes" {
  config_path = var.kubeconfig_path == "" ? null : var.kubeconfig_path
}
variable "kubeconfig_path" {
  type    = string
  default = ""
}
