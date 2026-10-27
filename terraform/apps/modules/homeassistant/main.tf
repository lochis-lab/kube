variable "namespace" { type = string }

resource "kubernetes_persistent_volume_claim_v1" "config" {
  metadata {
    name      = "ha-config"
    namespace = var.namespace
  }
  spec {
    access_modes      = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "10Gi" # immutable — matches live PVC exactly
      }
    }
  }
}

resource "kubernetes_deployment_v1" "home_assistant" {
  metadata {
    name      = "home-assistant"
    namespace = var.namespace
    labels    = { app = "home-assistant" }
  }
  spec {
    # Recreate: single replica on an RWO Longhorn PVC (RollingUpdate would
    # deadlock waiting for the old pod to release the volume).
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "home-assistant" }
    }
    template {
      metadata {
        labels = { app = "home-assistant" }
      }
      spec {
        container {
          name            = "home-assistant"
          image           = "docker.io/homeassistant/home-assistant:stable"
          image_pull_policy = "IfNotPresent"
          port {
            name        = "http"
            container_port = 8123
          }
          env {
            name  = "TZ"
            value = "America/Toronto"
          }
          readiness_probe {
            tcp_socket {
              port = 8123
            }
            initial_delay_seconds = 30
            period_seconds        = 15
            failure_threshold     = 10
          }
          liveness_probe {
            tcp_socket {
              port = 8123
            }
            initial_delay_seconds = 90
            period_seconds        = 30
          }
          resources {
            requests = { cpu = "100m", memory = "512Mi" }
            limits   = { memory = "2Gi" }
          }
          volume_mount {
            name       = "config"
            mount_path = "/config"
          }
        }
        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "ha_svc" {
  metadata {
    name      = "ha-svc"
    namespace = var.namespace
  }
  spec {
    selector = { app = "home-assistant" }
    port {
      name        = "http"
      port        = 8123
      target_port = 8123
    }
  }
}
