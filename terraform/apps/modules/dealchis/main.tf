variable "namespace" { type = string }

# Discord/ITAD deal-hunting bot. Single replica, no PVC, no Service —
# outbound bot only. Creds live in the pre-existing k8s Secret
# `dealchis-creds-secret` (unmanaged: referenced, never rendered);
# GHCR pull via pre-existing `reg-credentials-ghcr` in the namespace.
resource "kubernetes_deployment_v1" "dealchis_bot" {
  metadata {
    name      = "dealchis-bot"
    namespace = var.namespace
    labels    = { app = "dealchis-bot" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "dealchis-bot" }
    }
    template {
      metadata {
        labels = { app = "dealchis-bot" }
      }
      spec {
        container {
          name            = "dealchis-bot"
          image           = "ghcr.io/lochis/dealchis:0.0.1"
          image_pull_policy = "Always"
          port {
            container_port = 3000
          }
          env_from {
            secret_ref {
              name = "dealchis-creds-secret"
            }
          }
        }
        image_pull_secrets {
          name = "reg-credentials-ghcr"
        }
      }
    }
  }
}
