# openGym — passkey-authenticated workout tracker (github.com/DuarteSantos8/gym-app).
# Translated from upstream docker-compose.yml (docs/SELF_HOSTING.md):
#   compose `api` + `web` services -> one pod, two containers (web proxies
#   /api to api over localhost, they share a lifecycle)
#   compose `media` one-shot job   -> initContainer (git clone if img/ empty)
#   ./data volume                  -> opengym-data PVC (db.json + vapid.json —
#                                    the ONLY state; there is no database server)
#   ./media volume                 -> opengym-media PVC (~140 MB exercise imgs/gifs)
#   .env RP_ID/ORIGIN/RP_NAME      -> env below — NOT secrets, no TF_VAR plumbing.
#
# Passkeys (WebAuthn) bind to the exact RP_ID hostname and require HTTPS, so
# gym.vanderloch.com is final BEFORE anyone registers: changing RP_ID later
# invalidates every existing passkey.

variable "namespace" { type = string }

locals {
  host = "gym.vanderloch.com"
}

# ── Storage ─────────────────────────────────────────────────────────────────

# ./data: db.json, vapid.json, codex cache — tiny files, 1Gi is generous.
resource "kubernetes_persistent_volume_claim_v1" "opengym_data" {
  metadata {
    name      = "opengym-data"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "1Gi" } # immutable — read live size before ever changing
    }
  }
}

# ./media: ~140 MB dataset (hasaneyldrm/exercises-dataset), written once by
# the initContainer, read-only for web. RWX so the writer/reader never fight.
resource "kubernetes_persistent_volume_claim_v1" "opengym_media" {
  metadata {
    name      = "opengym-media"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "1Gi" } # 140 MB dataset + headroom
    }
  }
}

# ── Workload ────────────────────────────────────────────────────────────────

resource "kubernetes_deployment_v1" "opengym" {
  metadata {
    name      = "opengym"
    namespace = var.namespace
    labels    = { app = "opengym" }
  }
  spec {
    replicas = 1
    # Single replica on an RWO PVC: RollingUpdate surge pods deadlock on the
    # volume (repo rule). Recreate = kill-then-create.
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "opengym" }
    }
    template {
      metadata {
        labels = { app = "opengym" }
      }
      spec {
        # compose `media` service: one-shot dataset download, skipped when
        # img/ is already populated. $$ escapes to literal $ in heredocs.
        init_container {
          name    = "fetch-media"
          image   = "alpine/git@sha256:2306e2b05ee0ef99f5d25b0779f645b24ae9f91ba187107503592fcdfe78da3a" # 2.54.1
          command = ["/bin/sh", "-c", <<-EOT
            if [ -z "$$(ls -A /media/img 2>/dev/null)" ]; then
              echo "Downloading exercise media (~140 MB, one time)"
              git clone --depth 1 https://github.com/hasaneyldrm/exercises-dataset /tmp/ds
              cp /tmp/ds/images/*.jpg /media/img/ && cp /tmp/ds/videos/*.gif /media/gif/
              echo "Exercise media ready"
            else
              echo "Exercise media already present - skipping download"
            fi
          EOT
          ]
          volume_mount {
            name       = "media"
            mount_path = "/media"
          }
        }
        container {
          name  = "api"
          image = "ghcr.io/duartesantos8/opengym-api@sha256:397c83e9ac33a413bc8f21e66b2e55038100fc7f9da900d80be28b30fbb12ea8" # latest
          port {
            container_port = 3000
          }
          env {
            name  = "PORT"
            value = "3000"
          }
          env {
            name  = "DATA_DIR"
            value = "/data"
          }
          env {
            name  = "COACH_CODEX_HOME"
            value = "/codex"
          }
          # passkey origin config — exact-match the public URL
          env {
            name  = "RP_ID"
            value = local.host
          }
          env {
            name  = "ORIGIN"
            value = "https://${local.host}"
          }
          env {
            name  = "RP_NAME"
            value = "openGym"
          }
          readiness_probe {
            tcp_socket {
              port = 3000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "250m", memory = "256Mi" }
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          # compose: ./data/codex -> /codex (Coach CLI cache, separate mount)
          volume_mount {
            name       = "data"
            mount_path = "/codex"
            sub_path   = "codex"
          }
        }
        container {
          name  = "web"
          image = "ghcr.io/duartesantos8/opengym-web@sha256:e621677554302a0e1745e3b8c90acddc7d7149e118c4d683d51c13aa88f47d27" # latest
          port {
            container_port = 80
          }
          # /api/health proxies through nginx to the api container — gates
          # pod readiness on BOTH containers being up (compose's depends_on).
          readiness_probe {
            http_get {
              path = "/api/health"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "250m", memory = "256Mi" }
          }
          volume_mount {
            name       = "media"
            mount_path = "/usr/share/nginx/html/img"
            sub_path   = "img"
            read_only  = true
          }
          volume_mount {
            name       = "media"
            mount_path = "/usr/share/nginx/html/gif"
            sub_path   = "gif"
            read_only  = true
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.opengym_data.metadata[0].name
          }
        }
        volume {
          name = "media"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.opengym_media.metadata[0].name
          }
        }
      }
    }
  }
}

# ClusterIP is enough — external traffic arrives via cloudflare tunnel ->
# traefik outbound -> IngressRoute (ingress.tf); nothing hits this directly.
resource "kubernetes_service_v1" "opengym_svc" {
  metadata {
    name      = "opengym-svc"
    namespace = var.namespace
  }
  spec {
    type     = "ClusterIP"
    selector = { app = "opengym" }
    port {
      name        = "http"
      port        = 80
      target_port = 80
    }
  }
}
