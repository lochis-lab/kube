# State backend: Terraform `kubernetes` — state as Secret + Lease locking in ns `ops`.
# Chosen over S3/MinIO: MinIO community images are dead (removed from Docker Hub
# 2025-10, quay anonymous pulls disabled 2026-09 — minio/minio#21647). State backup
# rides on k3s etcd snapshots (3-master HA).
# Desktop init:   terraform init -backend-config=config_path=~/.kube/config
# Atlantis init:  in-cluster config (KUBERNETES_SERVICE_HOST) — no config_path.
terraform {
  backend "kubernetes" {
    namespace = "ops"
    secret_suffix = "kube-infra"
    labels = { managed_by = "terraform", repo = "kube" }
  }
}
