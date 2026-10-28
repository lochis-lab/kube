# Empty default = in-cluster provider config (Atlantis).
# Desktop: export TF_VAR_kubeconfig_path=$HOME/.kube/config
variable "kubeconfig_path" {
  description = "Path to kubeconfig for local runs; empty means in-cluster"
  type        = string
  default     = ""
}
