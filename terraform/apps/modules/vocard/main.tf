variable "namespace" { type = string }

resource "kubernetes_persistent_volume_claim_v1" "vocard_data" {
  metadata {
    name      = "vocard-pvc"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "1Gi" } # immutable — matches live PVC exactly
    }
  }
}

# reg-credentials-ghcr pull secret + vocard-dashboard-env stay unmanaged.

resource "kubernetes_deployment_v1" "vocard_bot" {
  metadata {
    name      = "vocard"
    namespace = var.namespace
  }
  spec {
    replicas = 1
    # Single replica on an RWO longhorn PVC: RollingUpdate deadlocks (new pod
    # can't attach the volume while the old one holds it, old one won't die
    # until the new is Ready). Recreate = kill-then-create. Proven necessary
    # during the 2026-10-28 lavalink-cutover restart.
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "vocard-bot" }
    }
    template {
      metadata {
        labels = { app = "vocard-bot" }
      }
      spec {
        automount_service_account_token = false # matches live (portainer-era)
        enable_service_links            = false
        # hostNetwork dropped 2026-10-30: portainer's klipper svclb claims hostPort
        # 8000 on every agent node, so a hostNetwork:8000 pod can never schedule
        # (stranded Pending after the k3s-1.34 svclb sprawl). Bot now gets normal
        # pod networking + the vocard-bot ClusterIP Service below.
        image_pull_secrets {
          name = "reg-credentials-ghcr"
        }
        container {
          name              = "vocard"
          image             = "ghcr.io/lochis/vocard-spookic-wip:v2.7.3.2" # own image, renovate-disabled
          image_pull_policy = "Always"
          port {
            container_port = 8000
          }
          volume_mount {
            name       = "vocard-data"
            mount_path = "/app/data"
          }
        }
        volume {
          name = "vocard-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.vocard_data.metadata[0].name
          }
        }
      }
    }
  }
  lifecycle {
    # Rancher re-adds field.cattle.io/publicEndpoints (hostNetwork pod);
    # portainer/cattle stamp template timestamps.
    ignore_changes = [metadata[0].annotations, spec[0].template[0].metadata[0].annotations]
  }
}

resource "kubernetes_deployment_v1" "vocard_dashboard" {
  metadata {
    name      = "vocard-dashboard"
    namespace = var.namespace
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "vocard-dashboard" }
    }
    template {
      metadata {
        labels = { app = "vocard-dashboard" }
      }
      spec {
        automount_service_account_token = false
        enable_service_links            = false
        container {
          name              = "vocard-dashboard"
          image             = "docker.io/lochis/spookic-dashboard:latest" # own image (docker hub)
          image_pull_policy = "Always"
          port {
            container_port = 8000
          }
          port {
            container_port = 2460
          }
          # all five env vars (PASSWORD/CLIENT_ID/CLIENT_SECRET_ID/SECRET_KEY/
          # REDIRECT_URL) moved out of the manifest into the unmanaged
          # vocard-dashboard-env Secret — nothing inline in the repo.
          env_from {
            secret_ref {
              name = "vocard-dashboard-env"
            }
          }
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations, spec[0].template[0].metadata[0].annotations]
  }
}

resource "kubernetes_service_v1" "vocard_bot" {
  metadata {
    name      = "vocard-bot"
    namespace = var.namespace
    labels    = { app = "vocard-bot" }
  }
  spec {
    selector = { app = "vocard-bot" }
    port {
      name        = "http"
      port        = 8000
      target_port = 8000
    }
  }
}

resource "kubernetes_service_v1" "vocard_dashboard" {
  metadata {
    name      = "vocard-dashboard"
    namespace = var.namespace
    labels    = { app = "vocard-dashboard" }
  }
  spec {
    selector = { app = "vocard-dashboard" }
    port {
      name        = "http"
      port        = 8000
      target_port = 8000
    }
    port {
      name        = "ipc"
      port        = 2460
      target_port = 2460
    }
  }
}
