terraform {
  required_version = "~> 1.17"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.4" }
    helm       = { source = "hashicorp/helm", version = "~> 3.3" }
  }
  # State backend: Terraform `kubernetes` — state as Secret + Lease locking in ns `ops`.
  # Secret: tfstate-default-kube-platform (matches atlantis.yaml project terraform-platform).
  # Desktop init:  terraform init -backend-config="config_path=$HOME/.kube/config"
  # Atlantis init: in-cluster config (KUBERNETES_SERVICE_HOST) — no config_path.
  backend "kubernetes" {
    namespace     = "ops"
    secret_suffix = "kube-platform"
    labels        = { managed_by = "terraform", repo = "kube" }
  }
}

# Desktop: TF_VAR_kubeconfig_path=~/.kube/config; Atlantis: in-cluster (empty default)
provider "kubernetes" {
  config_path = var.kubeconfig_path == "" ? null : var.kubeconfig_path
}

# helm provider v3 takes the kube connection as an argument (kubernetes = {...}),
# not as a nested block — the block form fails at import/plan time. The empty
# kubeconfig_path is mapped to null so both providers use the in-cluster config.
provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path == "" ? null : var.kubeconfig_path
  }
}
