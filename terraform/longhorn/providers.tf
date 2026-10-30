terraform {
  required_version = "~> 1.17"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.4" }
    helm       = { source = "hashicorp/helm", version = "~> 3.3" }
  }
  # Per-app root module (pilot of the per-app layout, 2026-10-30): own state as
  # Secret+Lease in ns ops, separate from terraform-platform.
  # Secret: tfstate-default-kube-longhorn (matches atlantis.yaml terraform-longhorn).
  backend "kubernetes" {
    namespace     = "ops"
    secret_suffix = "kube-longhorn"
    labels        = { managed_by = "terraform", repo = "kube" }
  }
}

# Desktop: TF_VAR_kubeconfig_path=~/.kube/config; Atlantis: in-cluster (empty default)
provider "kubernetes" {
  config_path = var.kubeconfig_path == "" ? null : var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path == "" ? null : var.kubeconfig_path
  }
}
