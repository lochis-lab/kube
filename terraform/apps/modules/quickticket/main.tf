# quickticket — dev + prod Postgres/Redis backing stacks.
#
# PROD POSTGRES IS DELIBERATELY ABSENT FROM THIS MODULE. Its PVC
# (quickticket-pgdata-prod) has been stuck Terminating since 2026-10-13 and
# its PV is marked for deletion, so the matching Deployment sits in
# ContainerCreating and can never start. Importing a terminating PVC is not
# sane; recreating it is a data-loss decision the repo owner must make.
# See the PR body for the two decision options.
variable "namespace" { type = string }

# quickticket-secret-dev / quickticket-secret-prod Secrets stay unmanaged
# (dealchis/n8n pattern): POSTGRES_PASSWORD + REDIS_PASSWORD are consumed via
# secret_key_ref only, never inlined here.

# --- PVCs (sizes are immutable — copied from the live claims) -------------

resource "kubernetes_persistent_volume_claim_v1" "pgdata_dev" {
  metadata {
    name      = "quickticket-pgdata-dev"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "2Gi" } # live: 2Gi
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "redis_data_dev" {
  metadata {
    name      = "quickticket-redis-data-dev"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "1Gi" } # live: 1Gi
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "redis_data_prod" {
  metadata {
    name      = "quickticket-redis-data-prod"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "2Gi" } # live: 2Gi
    }
  }
}

# --- Postgres (dev) -------------------------------------------------------

resource "kubernetes_deployment_v1" "postgres_dev" {
  metadata {
    name      = "quickticket-postgres-dev"
    namespace = var.namespace
    labels    = { app = "quickticket-postgres-dev" }
  }
  spec {
    # Recreate: single replica on an RWO Longhorn PVC (surge pods multi-attach).
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "quickticket-postgres-dev" }
    }
    template {
      metadata {
        labels = { app = "quickticket-postgres-dev" }
      }
      spec {
        automount_service_account_token = false # matches live
        enable_service_links            = false # matches live
        container {
          name              = "postgres"
          image             = "postgres:18.4-alpine" # live tag kept as-is
          image_pull_policy = "IfNotPresent"
          port {
            name           = "pg"
            container_port = 5432
          }
          env {
            name  = "POSTGRES_USER"
            value = "quickticket"
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
            name  = "POSTGRES_DB"
            value = "quickticket"
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }
          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "quickticket", "-d", "quickticket"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "quickticket", "-d", "quickticket"]
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
          volume_mount {
            name       = "pgdata"
            mount_path = "/var/lib/postgresql/data"
          }
        }
        volume {
          name = "pgdata"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.pgdata_dev.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "postgres_dev" {
  metadata {
    name      = "quickticket-postgres-dev"
    namespace = var.namespace
  }
  spec {
    selector = { app = "quickticket-postgres-dev" }
    port {
      name        = "pg"
      port        = 5432
      target_port = 5432
    }
  }
}

# --- Redis (dev + prod) ---------------------------------------------------

resource "kubernetes_deployment_v1" "redis_dev" {
  metadata {
    name      = "quickticket-redis-dev"
    namespace = var.namespace
    labels    = { app = "quickticket-redis-dev" }
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "quickticket-redis-dev" }
    }
    template {
      metadata {
        labels = { app = "quickticket-redis-dev" }
      }
      spec {
        automount_service_account_token = false # matches live
        enable_service_links            = false # matches live
        container {
          name              = "redis"
          image             = "redis:8.2.9-alpine" # live tag kept as-is
          image_pull_policy = "IfNotPresent"
          # requirepass comes from the env var below (secret-ref only).
          command = ["redis-server", "--requirepass", "$(REDIS_PASSWORD)", "--appendonly", "yes"]
          port {
            name           = "redis"
            container_port = 6379
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
          readiness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          liveness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
          resources {
            requests = { cpu = "25m", memory = "64Mi" }
            limits   = { cpu = "250m", memory = "256Mi" }
          }
          volume_mount {
            name       = "redis-data"
            mount_path = "/data"
          }
        }
        volume {
          name = "redis-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.redis_data_dev.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "redis_dev" {
  metadata {
    name      = "quickticket-redis-dev"
    namespace = var.namespace
  }
  spec {
    selector = { app = "quickticket-redis-dev" }
    port {
      name        = "redis"
      port        = 6379
      target_port = 6379
    }
  }
}

resource "kubernetes_deployment_v1" "redis_prod" {
  metadata {
    name      = "quickticket-redis-prod"
    namespace = var.namespace
    labels    = { app = "quickticket-redis-prod" }
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "quickticket-redis-prod" }
    }
    template {
      metadata {
        labels = { app = "quickticket-redis-prod" }
      }
      spec {
        automount_service_account_token = false # matches live
        enable_service_links            = false # matches live
        container {
          name              = "redis"
          image             = "redis:8.2.9-alpine" # live tag kept as-is
          image_pull_policy = "IfNotPresent"
          command           = ["redis-server", "--requirepass", "$(REDIS_PASSWORD)", "--appendonly", "yes"]
          port {
            name           = "redis"
            container_port = 6379
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
          readiness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          liveness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
          volume_mount {
            name       = "redis-data"
            mount_path = "/data"
          }
        }
        volume {
          name = "redis-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.redis_data_prod.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "redis_prod" {
  metadata {
    name      = "quickticket-redis-prod"
    namespace = var.namespace
  }
  spec {
    selector = { app = "quickticket-redis-prod" }
    port {
      name        = "redis"
      port        = 6379
      target_port = 6379
    }
  }
}
