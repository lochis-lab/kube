variable "namespace" { type = string }

resource "kubernetes_persistent_volume_claim_v1" "postgres_data" {
  metadata {
    name      = "postgres-pvc"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "10Gi" } # immutable — matches live PVC exactly
    }
  }
}

# n8n-secret + postgres-secret Secrets stay unmanaged (dealchis pattern):
# all creds flow through secretKeyRef env below, nothing inline to extract.

resource "kubernetes_stateful_set_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = var.namespace
    labels    = { app = "postgres" }
  }
  spec {
    replicas     = 1
    service_name = "postgres"
    selector {
      match_labels = { app = "postgres" }
    }
    template {
      metadata {
        labels = { app = "postgres" }
      }
      spec {
        automount_service_account_token = false # matches live (portainer-era); n8n needs no SA token
        enable_service_links            = false
        container {
          name  = "postgres"
          image = "docker.io/library/postgres:16-alpine" # major pinned (db-major strategy)
          port {
            container_port = 5432
          }
          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = "postgres-secret"
                key  = "POSTGRES_USER"
              }
            }
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = "postgres-secret"
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name = "POSTGRES_DB"
            value_from {
              secret_key_ref {
                name = "postgres-secret"
                key  = "POSTGRES_DB"
              }
            }
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }
          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "n8n", "-d", "n8n"]
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }
        }
        volume {
          name = "postgres-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.postgres_data.metadata[0].name
          }
        }
      }
    }
  }
}

# Headless svc — STS serviceName target (clusterIP None matches live).
resource "kubernetes_service_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = var.namespace
    labels    = { app = "postgres" }
  }
  spec {
    cluster_ip = "None"
    selector   = { app = "postgres" }
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

resource "kubernetes_deployment_v1" "n8n" {
  metadata {
    name      = "n8n"
    namespace = var.namespace
    labels    = { app = "n8n" }
  }
  spec {
    # Recreate: matches live deployment (single replica, no volume — but keeps
    # portainer-era strategy semantics; no RollingUpdate churn on digest bumps).
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "n8n" }
    }
    template {
      metadata {
        labels = { app = "n8n" }
      }
      spec {
        automount_service_account_token = false # matches live (portainer-era); n8n needs no SA token
        enable_service_links            = false # keep service env vars out of the container
        container {
          name = "n8n"
          # Rolling :latest tag — digest-pinned to the running image; Renovate
          # offers digest bumps (same as cloudreve/searxng).
          image             = "docker.io/n8nio/n8n@sha256:d02752c6ab446ae9db8deec2f9cc887c378f77cdcad31650814df936b7386dfb"
          image_pull_policy = "Always"
          port {
            name           = "http"
            container_port = 5678
          }
          env {
            name  = "DB_TYPE"
            value = "postgresdb"
          }
          env {
            name  = "DB_POSTGRESDB_HOST"
            value = "postgres.n8n.svc.cluster.local"
          }
          env {
            name  = "DB_POSTGRESDB_PORT"
            value = "5432"
          }
          env {
            name = "DB_POSTGRESDB_DATABASE"
            value_from {
              secret_key_ref {
                name = "postgres-secret"
                key  = "POSTGRES_DB"
              }
            }
          }
          env {
            name = "DB_POSTGRESDB_USER"
            value_from {
              secret_key_ref {
                name = "postgres-secret"
                key  = "POSTGRES_NON_ROOT_USER"
              }
            }
          }
          env {
            name = "DB_POSTGRESDB_PASSWORD"
            value_from {
              secret_key_ref {
                name = "n8n-secret"
                key  = "DB_POSTGRESDB_PASSWORD"
              }
            }
          }
          env {
            name = "N8N_ENCRYPTION_KEY"
            value_from {
              secret_key_ref {
                name = "n8n-secret"
                key  = "N8N_ENCRYPTION_KEY"
              }
            }
          }
          env {
            name  = "N8N_HOST"
            value = "n8n.example.com"
          }
          env {
            name  = "N8N_PORT"
            value = "5678"
          }
          env {
            name  = "N8N_PROTOCOL"
            value = "https"
          }
          env {
            name  = "WEBHOOK_URL"
            value = "https://n8n.vanderloch.com/"
          }
          env {
            name  = "N8N_EDITOR_BASE_URL"
            value = "https://n8n.vanderloch.com/"
          }
          env {
            name  = "NODE_ENV"
            value = "production"
          }
          env {
            name  = "N8N_DIAGNOSTICS_ENABLED"
            value = "false"
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = 5678
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 5678
            }
            initial_delay_seconds = 60
            period_seconds        = 30
          }
          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "1", memory = "1Gi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "n8n" {
  metadata {
    name      = "n8n"
    namespace = var.namespace
    labels    = { app = "n8n" }
  }
  spec {
    selector = { app = "n8n" }
    port {
      port        = 80
      target_port = 5678
    }
  }
}
