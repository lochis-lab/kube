variable "namespace" { type = string }

# reg-credentials-ghcr pull secret stays unmanaged (exists per-namespace).

resource "kubernetes_deployment_v1" "paloch_web" {
  metadata {
    name      = "paloch-web"
    namespace = var.namespace
    labels    = { app = "paloch-web" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "paloch-web" }
    }
    template {
      metadata {
        labels = { app = "paloch-web" }
      }
      spec {
        automount_service_account_token = false # matches live (portainer-era)
        enable_service_links             = false
        image_pull_secrets {
          name = "reg-credentials-ghcr"
        }
        container {
          name              = "paloch-web"
          image             = "ghcr.io/lochis/paloch:0.0.3" # own image, renovate-disabled
          image_pull_policy = "Always"
          port {
            name           = "http"
            container_port = 3000
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "paloch_web_service" {
  metadata {
    name      = "paloch-web-service"
    namespace = var.namespace
    labels    = { app = "paloch-web" }
  }
  spec {
    selector = { app = "paloch-web" }
    port {
      name        = "http"
      port        = 3000
      target_port = 3000
    }
  }
}
