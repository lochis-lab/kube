variable "namespace" { type = string }
variable "nfs_media_server" {
  type      = string
  sensitive = true
}

resource "kubernetes_persistent_volume_claim_v1" "config" {
  metadata {
      name = "abs-config"
      namespace = var.namespace
    }
  spec {
    access_modes      = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources { requests = { storage = "2Gi" } }
  }
}
# legacy pair RETIRED 2026-10-30: audiobookshelf-config/metadata were orphans
# (dead since 2025-11, superseded by abs-config/abs-metadata); user deleted them,
# and an accidental partial terraform apply recreated them empty — removed from
# management and deleted live in the same pass (volumes empty, nothing lost).
resource "kubernetes_persistent_volume_claim_v1" "metadata" {
  metadata {
      name = "abs-metadata"
      namespace = var.namespace
    }
  spec {
    access_modes      = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources { requests = { storage = "2Gi" } }
  }
}

resource "kubernetes_deployment_v1" "audiobookshelf" {
  metadata {
      name = "audiobookshelf"
      namespace = var.namespace
    }
  spec {
    replicas = 1
    selector { match_labels = { app = "audiobookshelf" } }
    strategy {
      type = "Recreate"
    } # RWO PVCs: no rolling surge
    template {
      metadata { labels = { app = "audiobookshelf" } }
      spec {
        container {
          name  = "audiobookshelf"
          image = "ghcr.io/advplyr/audiobookshelf:2.37.2"
          env {
      name = "TZ"
      value = "America/Toronto"
    }
          port {
      container_port = 80
    }
          port {
      container_port = 13378
    }
          volume_mount {
            name       = "config"
            mount_path = "/config"
          }
          volume_mount {
            name       = "metadata"
            mount_path = "/metadata"
          }
          volume_mount {
            name       = "audiobooks"
            mount_path = "/audiobooks"
          }
          volume_mount {
            name       = "podcasts"
            mount_path = "/podcasts"
          }
        }
        volume {
          name = "config"
          persistent_volume_claim {
      claim_name = kubernetes_persistent_volume_claim_v1.config.metadata[0].name
    }
        }
        volume {
          name = "metadata"
          persistent_volume_claim {
      claim_name = kubernetes_persistent_volume_claim_v1.metadata.metadata[0].name
    }
        }
        volume {
          name = "audiobooks"
          nfs {
      server = var.nfs_media_server
      path = "/srv/audiobooks"
    }
        }
        volume {
          name = "podcasts"
          nfs {
      server = var.nfs_media_server
      path = "/srv/podcasts"
    }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "audiobookshelf" {
  metadata {
      name = "audiobookshelf"
      namespace = var.namespace
    }
  spec {
    selector = { app = "audiobookshelf" }
    port {
      name        = "http"
      port        = 2459
      target_port = 80
    }
    port {
      name        = "ws"
      port        = 2460
      target_port = 13378
    }
  }
}
