# Empty default = in-cluster provider config (Atlantis).
# Desktop: export TF_VAR_kubeconfig_path=$HOME/.kube/config
variable "kubeconfig_path" {
  description = "Path to kubeconfig for local runs; empty means in-cluster"
  type        = string
  default     = ""
}

# Values arrive as TF_VAR_longhorn_backup_* injected by the Atlantis chart
# `environmentSecrets` from Secret `atlantis-app-vars` (ns ops) — never committed.
#
# Desktop plan: decode from atlantis-app-vars (see ~/Projects/kube/AGENTS.md pattern)
#   TF_VAR_longhorn_backup_access_key / _secret_key / _endpoint
variable "longhorn_backup_access_key" {
  description = "Garage S3 access key for the longhorn backup bucket (LONGHORN_BACKUP_ACCESS_KEY)"
  type        = string
  sensitive   = true
}

variable "longhorn_backup_secret_key" {
  description = "Garage S3 secret key for the longhorn backup bucket (LONGHORN_BACKUP_SECRET_KEY)"
  type        = string
  sensitive   = true
}

variable "longhorn_backup_endpoint" {
  description = "Garage S3 endpoint URL (LONGHORN_BACKUP_ENDPOINT); infra detail, never inline in this repo"
  type        = string
}
