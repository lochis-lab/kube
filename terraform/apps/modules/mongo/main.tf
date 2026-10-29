# mongo (ns default) — adopted 2026-11 from portainer stack 192.
# Sole in-cluster consumer: osu-tracker (svc DNS mongo.default.svc:27017).
# vocard/spookic uses Atlas cloud mongo — NOT this one.
# financial-planner DB (732K) has no in-cluster owner — VIP .160 kept until
# that's resolved (an external client may dial 192.168.10.160:27017).
variable "namespace" {
  type = string
}

variable "root_password" {
  type      = string
  sensitive = true
}

resource "kubernetes_persistent_volume_claim_v1" "mongo_data" {
  metadata {
    name      = "mongo-pvc"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "5Gi" } # immutable — matches live PVC exactly
    }
  }
}

resource "kubernetes_deployment_v1" "mongo" {
  metadata {
    name      = "mongo"
    namespace = var.namespace
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "mongo" }
    }
    template {
      metadata {
        labels = { app = "mongo" }
      }
      spec {
        container {
          name  = "mongo"
          image = "docker.io/library/mongo:8.2" # majors pinned by renovate rule + db-major-watch
          env {
            name  = "MONGO_INITDB_ROOT_USERNAME"
            value = "root"
          }
          env {
            name  = "MONGO_INITDB_ROOT_PASSWORD"
            value = var.root_password
          }
          volume_mount {
            name       = "mongo-data"
            mount_path = "/data/db"
          }
        }
        volume {
          name = "mongo-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.mongo_data.metadata[0].name
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations] # k3s/metallb re-add theirs every apply
  }
}

resource "kubernetes_service_v1" "mongo" {
  metadata {
    name      = "mongo"
    namespace = var.namespace
  }
  spec {
    type     = "LoadBalancer"
    selector = { app = "mongo" }
    port {
      name        = "mongo"
      port        = 27017
      target_port = 27017
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations] # k3s/metallb re-add theirs every apply
  }
}
