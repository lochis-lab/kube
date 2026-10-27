variable "namespace" { type = string }

# Secrets: none — headscale state (db.sqlite + noise keys) lives on the PVC;
# all config is in the two ConfigMaps below. lochis-tls cert is Reflector-managed.

# TAILNET CONTROL PLANE — a bad apply here cuts remote access. Extra care:
# - strategy Recreate (MIGRATIONS rule 4): live was RollingUpdate, but the RWO
#   Longhorn PVC multi-attach-traps a surge pod on a different node — that
#   deadlocks the rollout and holds the Atlantis apply lock. Recreate = brief
#   single-pod downtime instead of a hang. Applied deliberately in this import.
# - one rollout on adoption is expected anyway (console image :latest -> digest).
resource "kubernetes_deployment_v1" "headscale" {
  metadata {
    name      = "headscale"
    namespace = var.namespace
    labels    = { app = "headscale" }
  }
  # Rancher re-adds field.cattle.io/publicEndpoints on the deploy — ignore the
  # whole annotations map (same as ns/svc/osu-tracker deploy pattern).
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "headscale" }
    }
    strategy {
      type = "Recreate"
    }
    template {
      metadata {
        labels = { app = "headscale" }
      }
      spec {
        # portainer-era pod defaults preserved as-live (n8n/omniroute lesson)
        automount_service_account_token = false
        enable_service_links            = false
        container {
          name              = "headscale"
          image             = "headscale/headscale:v0.29.6"
          command           = ["headscale"]
          args              = ["serve"]
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 8080
          }
          port {
            container_port = 50443
          }
          port {
            container_port = 2459
          }
          port {
            container_port = 3478
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/headscale"
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/headscale"
          }
          volume_mount {
            name       = "socket"
            mount_path = "/var/run/headscale"
          }
        }
        container {
          name              = "headscale-console"
          image             = "ghcr.io/rickli-cloud/headscale-console@sha256:4bdd88593befb32e982d3b44245fd8f06909e4c325d952f02baffc673635d6a7" # 0.7.3 — old digest was a stale pre-static build that 404'd every path
          command           = ["headscale-console"]
          args              = ["serve"]
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 3000
          }
          volume_mount {
            name       = "console-config"
            mount_path = "/config.json"
            sub_path   = "config.json"
          }
          volume_mount {
            name       = "socket"
            mount_path = "/var/run/headscale"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.config.metadata[0].name
            items {
              key  = "config.yaml"
              path = "config.yaml"
            }
          }
        }
        volume {
          name = "console-config"
          config_map {
            name = kubernetes_config_map_v1.console_config.metadata[0].name
            items {
              key  = "config.json"
              path = "config.json"
            }
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.data.metadata[0].name
          }
        }
        volume {
          name = "socket"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "headscale" {
  metadata {
    name      = "headscale"
    namespace = var.namespace
  }
  spec {
    type     = "ClusterIP"
    selector = { app = "headscale" }
    port {
      name        = "web"
      port        = 8080
      target_port = 8080
    }
    port {
      name        = "grpc"
      port        = 50443
      target_port = 50443
    }
    port {
      name        = "derp"
      port        = 2459
      protocol    = "TCP"
      target_port = 2459
    }
    port {
      name        = "stun"
      port        = 3478
      protocol    = "UDP"
      target_port = 3478
    }
    port {
      name        = "metrics"
      port        = 9090
      target_port = 9090
    }
  }
  # Rancher re-adds field.cattle.io/publicEndpoints — controller-maintained.
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "data" {
  metadata {
    name      = "headscale-pvc"
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
