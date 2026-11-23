# ntfy — self-hosted push notification service (pub/sub).
# TAILNET/LAN-ONLY by design: IngressRoute on websecure :443 + Pi-hole local
# DNS (192.168.10.170), NO Cloudflare tunnel entry — the hostname never
# leaves the homelab. Publishers: automations (gmail-digest deliver.sh on
# happy-agent-01). Subscribers: the ntfy phone app over Headscale.
# No token auth: only tailnet devices can reach it. Revisit if the tailnet
# ever grows beyond personal machines.

variable "namespace" { type = string }

locals {
  ntfy_img = "binwiederhier/ntfy:v2.38.1" # renovate bumps
}

# --- cache (message cache + attachments) ----------------------------------
resource "kubernetes_persistent_volume_claim_v1" "cache" {
  metadata {
    name      = "ntfy-cache"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "1Gi" }
    }
  }
}

# --- ntfy -------------------------------------------------------------------
resource "kubernetes_deployment_v1" "ntfy" {
  metadata {
    name      = "ntfy"
    namespace = var.namespace
    labels    = { app = "ntfy" }
  }
  spec {
    replicas = 1
    strategy { type = "Recreate" } # RWO PVC
    selector {
      match_labels = { app = "ntfy" }
    }
    template {
      metadata { labels = { app = "ntfy" } }
      spec {
        container {
          name  = "ntfy"
          image = local.ntfy_img
          args  = ["serve"]
          port {
            container_port = 80
          }
          env {
            name  = "NTFY_BASE_URL"
            value = "https://ntfy.vanderloch.com"
          }
          env {
            # iOS instant delivery: without an APNs-connected upstream, iOS
            # delivers only on app-wake (minutes-to-hours late). What transits
            # ntfy.sh: a contentless poll_request — message ID + SHA-256 of
            # the topic name; the upstream body is literally "New message".
            # Real content is always fetched from THIS server (tailnet).
            # base-url must exactly match the server URL in the iOS app.
            name  = "NTFY_UPSTREAM_BASE_URL"
            value = "https://ntfy.sh"
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              memory = "256Mi"
            }
          }
          liveness_probe {
            http_get {
              path = "/v1/health"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 30
          }
          volume_mount {
            name       = "cache"
            mount_path = "/var/cache/ntfy"
          }
        }
        volume {
          name = "cache"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.cache.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "ntfy" {
  metadata {
    name      = "ntfy"
    namespace = var.namespace
  }
  spec {
    selector = { app = "ntfy" }
    port {
      port        = 80
      target_port = 80
    }
  }
}
