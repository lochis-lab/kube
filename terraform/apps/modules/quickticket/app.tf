# QuickTicket app itself (API + web), dev and prod, added 2026-11.
#
# Wiring:
#   dev  -> quickticket-postgres-dev / quickticket-redis-dev   (existing, this module)
#   prod -> quickticket-postgres-prod / quickticket-redis-prod (existing, this module)
#
# Tag policy:
#   dev  tracks the moving :dev tag (CI pushes it on every merge to main,
#        then rollout-restarts this deployment) -> image_pull_policy Always.
#   prod is pinned; only moves via a deliberate tag-bump PR through Atlantis.
#
# Passwords come from the pre-existing external secrets quickticket-secret-{dev,prod}
# (keys POSTGRES_PASSWORD / REDIS_PASSWORD). Dependent env expansion (k8s "$(VAR)",
# referenced var must be declared first) composes them into the connection URLs.
#
# GHCR packages (ghcr.io/thegamecracks/quickticket-{api,web}) are PUBLIC
# (published via GITHUB_TOKEN from the public repo, visibility inherited), so
# the cluster pulls them anonymously. NO pull secret is required.
#
# Every pod spec below nonetheless references an imagePullSecret named
# "ghcr-pull" as a deliberate no-op placeholder: kubelet ignores a missing
# secret and pulls anonymously. If the packages are ever made PRIVATE, the
# entire fix is creating that one secret (no terraform change):
#
#   kubectl -n quickticket create secret docker-registry ghcr-pull \
#     --docker-server=ghcr.io \
#     --docker-username=<github-user> \
#     --docker-password=<classic PAT, read:packages scope>
#
# Images don't exist until the quickticket repo's CI publishes its first
# :dev builds, so pods ImagePullBackOff until then. Expected; self-heals.

# ---------------------------------------------------------------- api (dev) --
resource "kubernetes_deployment_v1" "api_dev" {
  metadata {
    name      = "quickticket-dev"
    namespace = var.namespace
    labels    = { app = "quickticket-dev" }
  }
  spec {
    # Recreate: alembic migrations run at container start; never two pods at once.
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "quickticket-dev" }
    }
    template {
      metadata {
        labels = { app = "quickticket-dev" }
      }
      spec {
        automount_service_account_token = false # house style
        enable_service_links            = false # house style
        container {
          name              = "api"
          image             = "ghcr.io/thegamecracks/quickticket-api:dev"
          image_pull_policy = "Always" # pick up :dev rebuilds without tag change
          # ENTRYPOINT is ["uv","run"], so this becomes: uv run sh -c "..."
          command = ["sh", "-c", "alembic upgrade head && quickticket run"]
          port {
            name           = "http"
            container_port = 8000
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = "quickticket-secret-dev"
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = "quickticket-secret-dev"
                key  = "REDIS_PASSWORD"
              }
            }
          }
          # dependent env expansion — must come after the two vars above
          env {
            name  = "BACKEND__DB__URL"
            value = "postgresql+psycopg://quickticket:$(POSTGRES_PASSWORD)@quickticket-postgres-dev.${var.namespace}.svc.cluster.local:5432/quickticket"
          }
          env {
            name  = "BACKEND__CACHE__URL"
            value = "redis://default:$(REDIS_PASSWORD)@quickticket-redis-dev.${var.namespace}.svc.cluster.local:6379/0"
          }
          readiness_probe {
            tcp_socket {
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          liveness_probe {
            tcp_socket {
              port = "http"
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "api_dev" {
  metadata {
    name      = "quickticket-dev"
    namespace = var.namespace
  }
  spec {
    selector = { app = "quickticket-dev" }
    port {
      name       = "http"
      port       = 8000
      target_port = "http"
    }
  }
}

# --------------------------------------------------------------- web (dev) --
resource "kubernetes_deployment_v1" "web_dev" {
  metadata {
    name      = "quickticket-dev-web"
    namespace = var.namespace
    labels    = { app = "quickticket-dev-web" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "quickticket-dev-web" }
    }
    template {
      metadata {
        labels = { app = "quickticket-dev-web" }
      }
      spec {
        automount_service_account_token = false
        enable_service_links            = false
        container {
          name              = "web"
          image             = "ghcr.io/thegamecracks/quickticket-web:dev"
          image_pull_policy = "Always"
          port {
            name           = "http"
            container_port = 80
          }
          readiness_probe {
            tcp_socket {
              port = "http"
            }
            initial_delay_seconds = 3
            period_seconds        = 10
          }
          liveness_probe {
            tcp_socket {
              port = "http"
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }
          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { cpu = "200m", memory = "128Mi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "web_dev" {
  metadata {
    name      = "quickticket-dev-web"
    namespace = var.namespace
  }
  spec {
    selector = { app = "quickticket-dev-web" }
    port {
      name       = "http"
      port       = 80
      target_port = "http"
    }
  }
}

# --------------------------------------------------------------- api (prod) --
resource "kubernetes_deployment_v1" "api_prod" {
  metadata {
    name      = "quickticket-prod"
    namespace = var.namespace
    labels    = { app = "quickticket-prod" }
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "quickticket-prod" }
    }
    template {
      metadata {
        labels = { app = "quickticket-prod" }
      }
      spec {
        automount_service_account_token = false
        enable_service_links            = false
        container {
          name              = "api"
          # PROMOTION = bump this tag in a PR (Atlantis plans/applies it)
          image             = "ghcr.io/thegamecracks/quickticket-api:1.0.0"
          image_pull_policy = "IfNotPresent"
          command = ["sh", "-c", "alembic upgrade head && quickticket run"]
          port {
            name           = "http"
            container_port = 8000
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = "quickticket-secret-prod"
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = "quickticket-secret-prod"
                key  = "REDIS_PASSWORD"
              }
            }
          }
          env {
            name  = "BACKEND__DB__URL"
            value = "postgresql+psycopg://quickticket:$(POSTGRES_PASSWORD)@quickticket-postgres-prod.${var.namespace}.svc.cluster.local:5432/quickticket"
          }
          env {
            name  = "BACKEND__CACHE__URL"
            value = "redis://default:$(REDIS_PASSWORD)@quickticket-redis-prod.${var.namespace}.svc.cluster.local:6379/0"
          }
          readiness_probe {
            tcp_socket {
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          liveness_probe {
            tcp_socket {
              port = "http"
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "1", memory = "1Gi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "api_prod" {
  metadata {
    name      = "quickticket-prod"
    namespace = var.namespace
  }
  spec {
    selector = { app = "quickticket-prod" }
    port {
      name       = "http"
      port       = 8000
      target_port = "http"
    }
  }
}

# -------------------------------------------------------------- web (prod) --
resource "kubernetes_deployment_v1" "web_prod" {
  metadata {
    name      = "quickticket-prod-web"
    namespace = var.namespace
    labels    = { app = "quickticket-prod-web" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "quickticket-prod-web" }
    }
    template {
      metadata {
        labels = { app = "quickticket-prod-web" }
      }
      spec {
        automount_service_account_token = false
        enable_service_links            = false
        container {
          name              = "web"
          # PROMOTION = bump this tag in the same PR as the api tag above
          image             = "ghcr.io/thegamecracks/quickticket-web:1.0.0"
          image_pull_policy = "IfNotPresent"
          port {
            name           = "http"
            container_port = 80
          }
          readiness_probe {
            tcp_socket {
              port = "http"
            }
            initial_delay_seconds = 3
            period_seconds        = 10
          }
          liveness_probe {
            tcp_socket {
              port = "http"
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }
          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { cpu = "200m", memory = "128Mi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "web_prod" {
  metadata {
    name      = "quickticket-prod-web"
    namespace = var.namespace
  }
  spec {
    selector = { app = "quickticket-prod-web" }
    port {
      name       = "http"
      port       = 80
      target_port = "http"
    }
  }
}
