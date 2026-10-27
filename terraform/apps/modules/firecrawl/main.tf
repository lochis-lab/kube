variable "namespace" { type = string }

locals {
  firecrawl_img = "ghcr.io/firecrawl/firecrawl@sha256:30dbc0fd054cab35ba321fba24100d8a5c304335012cb7029cd15df4cdfb9e5c"
}

# --- shared config + secret ----------------------------------------------
# firecrawl-secret (12 keys: OPENAI_API_KEY, NUQ_DATABASE_URL, POSTGRES_/
# REDIS_/PROXY_* creds, ...) is a pre-existing unmanaged k8s Secret,
# referenced only — same convention as dealchis-creds-secret.
resource "kubernetes_config_map_v1" "config" {
  metadata {
    name      = "firecrawl-config"
    namespace = var.namespace
  }
  data = {
    ENV                          = "production"
    HOST                         = "0.0.0.0"
    IS_KUBERNETES                = "true"
    LOGGING_LEVEL                = "INFO"
    PLAYWRIGHT_MICROSERVICE_URL  = "http://playwright-service:3000"
    SEARXNG_ENDPOINT             = "http://searxng.searxng.svc:8080"
    SENTRY_ENVIRONMENT           = "selfhosted"
    USE_DB_AUTHENTICATION        = "false"
  }
}

# --- state ---------------------------------------------------------------
resource "kubernetes_persistent_volume_claim_v1" "pgdata" {
  metadata {
    name      = "firecrawl-pgdata"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "10Gi" } # immutable — matches live
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "redis" {
  metadata {
    name      = "firecrawl-redis"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "2Gi" } # immutable — matches live
    }
  }
}

# --- postgres (nuq) --------------------------------------------------------
resource "kubernetes_deployment_v1" "nuq_postgres" {
  metadata {
    name      = "nuq-postgres"
    namespace = var.namespace
    labels    = { app = "nuq-postgres" }
  }
  spec {
    replicas = 1
    strategy { type = "Recreate" } # RWO PVC
    selector {
      match_labels = { app = "nuq-postgres" }
    }
    template {
      metadata {
        labels = { app = "nuq-postgres" }
      }
      spec {
        container {
          name            = "nuq-postgres"
          image           = "ghcr.io/firecrawl/nuq-postgres@sha256:d719b36160eac2fcbe16dc7e7360ddb9c82c40ea5da183d07bf4a755c6a0b2ae"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 5432
          }
          env {
            name  = "POSTGRES_USER"
            value = "postgres"
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = "firecrawl-secret"
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name  = "POSTGRES_DB"
            value = "postgres"
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }
          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres"]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "1", memory = "1Gi" }
          }
          volume_mount {
            name       = "pgdata"
            mount_path = "/var/lib/postgresql/data"
          }
        }
        volume {
          name = "pgdata"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.pgdata.metadata[0].name
          }
        }
      }
    }
  }
}

# --- redis -----------------------------------------------------------------
resource "kubernetes_deployment_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = var.namespace
    labels    = { app = "redis" }
  }
  spec {
    replicas = 1
    strategy { type = "Recreate" } # RWO PVC
    selector {
      match_labels = { app = "redis" }
    }
    template {
      metadata {
        labels = { app = "redis" }
      }
      spec {
        container {
          name            = "redis"
          image           = "docker.io/library/redis:alpine"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 6379
          }
          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = "firecrawl-secret"
                key  = "REDIS_PASSWORD"
              }
            }
          }
          command = ["/bin/sh", "-c"]
          args = ["exec redis-server --bind 0.0.0.0 \\\n  --requirepass \"$REDIS_PASSWORD\" \\\n  --appendonly yes\n"]
          readiness_probe {
            exec {
              command = ["sh", "-c", "redis-cli -a \"$REDIS_PASSWORD\" ping | grep PONG"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.redis.metadata[0].name
          }
        }
      }
    }
  }
}

# --- playwright-service ------------------------------------------------------
resource "kubernetes_deployment_v1" "playwright_service" {
  metadata {
    name      = "playwright-service"
    namespace = var.namespace
    labels    = { app = "playwright-service" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "playwright-service" }
    }
    template {
      metadata {
        labels = { app = "playwright-service" }
      }
      spec {
        security_context {
          run_as_user    = 1000
          run_as_group   = 1000
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name            = "playwright-service"
          image           = "ghcr.io/firecrawl/playwright-service@sha256:637fb8c8399634b02c2179da72566ce11644435e5d93e895bdbde4b1f9b0882a"
          image_pull_policy = "Always"
          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
          port {
            container_port = 3000
          }
          env {
            name  = "PORT"
            value = "3000"
          }
          env {
            name  = "ALLOW_LOCAL_WEBHOOKS"
            value = "false"
          }
          env {
            name = "PROXY_SERVER"
            value_from {
              secret_key_ref {
                name = "firecrawl-secret"
                key  = "PROXY_SERVER"
              }
            }
          }
          env {
            name = "PROXY_USERNAME"
            value_from {
              secret_key_ref {
                name = "firecrawl-secret"
                key  = "PROXY_USERNAME"
              }
            }
          }
          env {
            name = "PROXY_PASSWORD"
            value_from {
              secret_key_ref {
                name = "firecrawl-secret"
                key  = "PROXY_PASSWORD"
              }
            }
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }
          resources {
            requests = { cpu = "100m", memory = "512Mi" }
            limits   = { cpu = "1", memory = "2Gi" }
          }
        }
      }
    }
  }
}

# --- api -------------------------------------------------------------------
resource "kubernetes_deployment_v1" "api" {
  metadata {
    name      = "api"
    namespace = var.namespace
    labels    = { app = "api" }
  }
  spec {
    replicas = 1
    strategy { type = "Recreate" }
    selector {
      match_labels = { app = "api" }
    }
    template {
      metadata {
        labels = { app = "api" }
      }
      spec {
        termination_grace_period_seconds = 120 # scrape-job drain window
        container {
          name            = "api"
          image           = local.firecrawl_img
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 3002
          }
          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.config.metadata[0].name
            }
          }
          env_from {
            secret_ref {
              name = "firecrawl-secret"
            }
          }
          env {
            name  = "FLY_PROCESS_GROUP"
            value = "app"
          }
          env {
            name  = "PORT"
            value = "3002"
          }
          command = ["node"]
          args    = ["--max-old-space-size=1536", "dist/src/index.js"]
          readiness_probe {
            http_get {
              path = "/v0/health/readiness"
              port = 3002
            }
            initial_delay_seconds = 30
            period_seconds        = 15
          }
          liveness_probe {
            http_get {
              path = "/v0/health/liveness"
              port = 3002
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }
          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "1", memory = "2Gi" }
          }
        }
      }
    }
  }
}

# --- queue worker ------------------------------------------------------------
resource "kubernetes_deployment_v1" "worker" {
  metadata {
    name      = "worker"
    namespace = var.namespace
    labels    = { app = "worker" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "worker" }
    }
    template {
      metadata {
        labels = { app = "worker" }
      }
      spec {
        termination_grace_period_seconds = 60 # in-flight job drain window
        container {
          name            = "worker"
          image           = local.firecrawl_img
          image_pull_policy = "IfNotPresent"
          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.config.metadata[0].name
            }
          }
          env_from {
            secret_ref {
              name = "firecrawl-secret"
            }
          }
          env {
            name  = "FLY_PROCESS_GROUP"
            value = "worker"
          }
          env {
            name  = "PORT"
            value = "3005"
          }
          command = ["node"]
          args    = ["--max-old-space-size=1024", "dist/src/services/queue-worker.js"]
          liveness_probe {
            http_get {
              path = "/liveness"
              port = 3005
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "1", memory = "1536Mi" }
          }
        }
      }
    }
  }
}

# --- nuq worker ----------------------------------------------------------------
resource "kubernetes_deployment_v1" "nuq_worker" {
  metadata {
    name      = "nuq-worker"
    namespace = var.namespace
    labels    = { app = "nuq-worker" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "nuq-worker" }
    }
    template {
      metadata {
        labels = { app = "nuq-worker" }
      }
      spec {
        termination_grace_period_seconds = 60 # in-flight job drain window
        container {
          name            = "nuq-worker"
          image           = local.firecrawl_img
          image_pull_policy = "IfNotPresent"
          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.config.metadata[0].name
            }
          }
          env_from {
            secret_ref {
              name = "firecrawl-secret"
            }
          }
          env {
            name  = "FLY_PROCESS_GROUP"
            value = "nuq-worker"
          }
          env {
            name  = "NUQ_WORKER_PORT"
            value = "3006"
          }
          command = ["node"]
          args    = ["--max-old-space-size=1024", "dist/src/services/worker/nuq-worker.js"]
          liveness_probe {
            http_get {
              path = "/health"
              port = 3006
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "1", memory = "1536Mi" }
          }
        }
      }
    }
  }
}

# --- services ----------------------------------------------------------------
resource "kubernetes_service_v1" "api" {
  metadata {
    name      = "api"
    namespace = var.namespace
  }
  spec {
    selector = { app = "api" }
    port {
      port        = 3002
      target_port = 3002
    }
  }
}

resource "kubernetes_service_v1" "nuq_postgres" {
  metadata {
    name      = "nuq-postgres"
    namespace = var.namespace
  }
  spec {
    selector = { app = "nuq-postgres" }
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

resource "kubernetes_service_v1" "playwright_service" {
  metadata {
    name      = "playwright-service"
    namespace = var.namespace
  }
  spec {
    selector = { app = "playwright-service" }
    port {
      port        = 3000
      target_port = 3000
    }
  }
}

resource "kubernetes_service_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = var.namespace
  }
  spec {
    selector = { app = "redis" }
    port {
      port        = 6379
      target_port = 6379
    }
  }
}
