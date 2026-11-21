# openGym — passkey-authenticated workout tracker (github.com/DuarteSantos8/gym-app).
# Translated from upstream docker-compose.yml (docs/SELF_HOSTING.md):
#   compose `api` service    -> deployment opengym-api + Service `api`
#   compose `web` service    -> deployment opengym-web + Service opengym-svc
#   compose `media` one-shot -> initContainer on web (git clone if img/ empty)
#   ./data volume            -> opengym-data PVC (db.json + vapid.json —
#                               the ONLY state; there is no database server)
#   ./media volume           -> opengym-media PVC (~140 MB exercise imgs/gifs)
#
# Topology note (learned the hard way): web's nginx proxies /api to the
# HOSTNAME `api` baked in at build time for compose DNS. The api workload MUST
# be reachable as Service `api` in this namespace — a sidecar container in a
# shared pod has no DNS name and the proxy 499s forever.
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
# the initContainer, read-only for web. RWX so writer/reader never fight
# (also the cluster's first RWX volume — needs longhorn share-manager, which
# exists and works; see PR notes for the multipathd incident on first boot).
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

# ── API (compose `api`) ─────────────────────────────────────────────────────

resource "kubernetes_deployment_v1" "opengym_api" {
  metadata {
    name      = "opengym-api"
    namespace = var.namespace
    labels    = { app = "opengym-api" }
  }
  spec {
    replicas = 1
    # Single replica on an RWO PVC: RollingUpdate surge pods deadlock on the
    # volume. Recreate = kill-then-create (repo rule).
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "opengym-api" }
    }
    template {
      metadata {
        labels = { app = "opengym-api" }
      }
      spec {
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
            http_get {
              path = "/api/health"
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
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.opengym_data.metadata[0].name
          }
        }
      }
    }
  }
}

# Named exactly `api` — web's baked nginx config proxies to hostname `api`
# (compose service discovery); the k8s Service reproduces that name.
resource "kubernetes_service_v1" "api" {
  metadata {
    name      = "api"
    namespace = var.namespace
  }
  spec {
    type     = "ClusterIP"
    selector = { app = "opengym-api" }
    port {
      name        = "http"
      port        = 3000
      target_port = 3000
    }
  }
}

# ── WEB (compose `web`) ─────────────────────────────────────────────────────

resource "kubernetes_deployment_v1" "opengym_web" {
  metadata {
    name      = "opengym-web"
    namespace = var.namespace
    labels    = { app = "opengym-web" }
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate" # single RWX consumer, keep updates boring
    }
    selector {
      match_labels = { app = "opengym-web" }
    }
    template {
      metadata {
        labels = { app = "opengym-web" }
      }
      spec {
        # compose `media` service: one-shot dataset download, skipped when
        # img/ is already populated. mkdir -p first — a fresh PVC has no
        # subdirs (compose relied on pre-existing host bind-mount dirs).
        # $$ escapes to literal $ in heredocs.
        init_container {
          name    = "fetch-media"
          image   = "alpine/git@sha256:2306e2b05ee0ef99f5d25b0779f645b24ae9f91ba187107503592fcdfe78da3a" # 2.54.1
          command = ["/bin/sh", "-c", <<-EOT
            mkdir -p /media/img /media/gif
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
          name  = "web"
          image = "ghcr.io/duartesantos8/opengym-web@sha256:e621677554302a0e1745e3b8c90acddc7d7149e118c4d683d51c13aa88f47d27" # latest
          port {
            container_port = 80
          }
          # The image's nginx template defaults to Docker's embedded DNS
          # (127.0.0.11) for the /api proxy resolver — nothing answers there
          # in k8s, so every /api request hung. Upstream-sanctioned switch
          # (15-local-resolvers.envsh): read the nameservers from
          # /etc/resolv.conf instead -> kube-dns, no IP hardcoded.
          env {
            name  = "NGINX_ENTRYPOINT_LOCAL_RESOLVERS"
            value = "1"
          }
          # /api/health proxies through nginx to Service `api` — gates pod
          # readiness on the whole chain (compose's depends_on equivalent).
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
    selector = { app = "opengym-web" }
    port {
      name        = "http"
      port        = 80
      target_port = 80
    }
  }
}
