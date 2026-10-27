variable "namespace" { type = string }

# tailscale sidecar state + auth: secrets `omniroute-tailscale` (state, written
# by the sidecar via TS_KUBE_SECRET — NEVER manage in TF) and `tailscale-auth`
# (authkey) both stay unmanaged.

resource "kubernetes_service_account_v1" "tailscale" {
  metadata {
    name      = "tailscale"
    namespace = var.namespace
  }
  automount_service_account_token = true # sidecar reads the token to write its state secret
}

resource "kubernetes_role_v1" "tailscale" {
  metadata {
    name      = "tailscale"
    namespace = var.namespace
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "create", "update", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "tailscale" {
  metadata {
    name      = "tailscale"
    namespace = var.namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.tailscale.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.tailscale.metadata[0].name
    namespace = var.namespace
  }
}

resource "kubernetes_persistent_volume_claim_v1" "omniroute_data" {
  metadata {
    name      = "omniroute-data"
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

resource "kubernetes_persistent_volume_claim_v1" "tailscale_state" {
  metadata {
    name      = "tailscale-state"
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

resource "kubernetes_deployment_v1" "omniroute" {
  metadata {
    name      = "omniroute"
    namespace = var.namespace
    labels    = { app = "omniroute" }
  }
  spec {
    # Recreate: single replica on two RWO Longhorn PVCs.
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "omniroute" }
    }
    template {
      metadata {
        labels = { app = "omniroute" }
      }
      spec {
        service_account_name            = kubernetes_service_account_v1.tailscale.metadata[0].name
        automount_service_account_token = true # tailscale sidecar inits kube client (TS_KUBE_SECRET) — needs the SA token
        enable_service_links            = false
        container {
          name = "omniroute"
          # :latest tags — digest-pinned to running images (Renovate offers bumps)
          image             = "docker.io/diegosouzapw/omniroute@sha256:b08a12e876baa8a5ccadd1ebbe346fe7267dba3b1c9f4fd6bb02070fae41ab6c"
          image_pull_policy = "Always"
          port {
            container_port = 20128
          }
          env {
            name  = "USAGE_TOKEN_BUFFER"
            value = "50"
          }
          env {
            name  = "DATA_DIR"
            value = "/app/data"
          }
          readiness_probe {
            tcp_socket {
              port = 20128
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
          liveness_probe {
            tcp_socket {
              port = 20128
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }
          resources {
            requests = { cpu = "100m", memory = "512Mi" }
            limits   = { cpu = "1", memory = "1536Mi" }
          }
          security_context {
            run_as_user                = 0
            allow_privilege_escalation = false # matches live
          }
          volume_mount {
            name       = "data"
            mount_path = "/app/data"
          }
        }
        container {
          name              = "tailscale"
          image             = "ghcr.io/tailscale/tailscale@sha256:b11583ad2e93e4671128538c88cf11f460444a5d7e449311dd1933a400ab849d"
          image_pull_policy = "Always"
          env {
            name  = "TS_USERSPACE"
            value = "false"
          }
          env {
            name = "TS_AUTHKEY"
            value_from {
              secret_key_ref {
                name = "tailscale-auth"
                key  = "TS_AUTHKEY"
              }
            }
          }
          env {
            name  = "TS_EXTRA_ARGS"
            value = "--login-server https://headscale.vanderloch.com:2459"
          }
          env {
            name  = "TS_KUBE_SECRET"
            value = "omniroute-tailscale"
          }
          env {
            name  = "TS_HOSTNAME"
            value = "omniroute-pod"
          }
          security_context {
            allow_privilege_escalation = false # matches live
            capabilities {
              add = ["NET_ADMIN"]
            }
          }
          volume_mount {
            name       = "ts-state"
            mount_path = "/var/lib/tailscale"
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.omniroute_data.metadata[0].name
          }
        }
        volume {
          name = "ts-state"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.tailscale_state.metadata[0].name
          }
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations, spec[0].template[0].metadata[0].annotations]
  }
}

resource "kubernetes_service_v1" "omniroute_svc" {
  metadata {
    name      = "omniroute-svc"
    namespace = var.namespace
    labels    = { app = "omniroute" }
  }
  spec {
    selector = { app = "omniroute" }
    port {
      port        = 20128
      target_port = 20128
    }
  }
}
