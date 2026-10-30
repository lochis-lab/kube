variable "namespace" { type = string }

# Secrets stay unmanaged: auto-school-env, auto-school-pg, auto-school-basicauth
# + reg-credentials-ghcr pull secret. All creds flow via secretKeyRef/envFrom.

resource "kubernetes_persistent_volume_claim_v1" "data" {
  metadata {
    name      = "auto-school-data"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "60Gi" } # immutable — PVC was expanded 40->60Gi; spec.requests = 64424509440
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "pgdata" {
  metadata {
    name      = "auto-school-pgdata"
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

resource "kubernetes_deployment_v1" "auto_school_pg" {
  metadata {
    name      = "auto-school-pg"
    namespace = var.namespace
    labels    = { app = "auto-school-pg" }
  }
  spec {
    # Recreate: single replica on an RWO Longhorn PVC.
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "auto-school-pg" }
    }
    template {
      metadata {
        labels = { app = "auto-school-pg" }
      }
      spec {
        automount_service_account_token = false # matches live
        enable_service_links            = false
        container {
          name = "postgres"
          # pgvector major tag == postgres major — pinned per db-major strategy
          image             = "docker.io/pgvector/pgvector:pg17"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 5432
          }
          env {
            name  = "POSTGRES_DB"
            value = "autoschool"
          }
          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = "auto-school-pg"
                key  = "PGUSER"
              }
            }
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = "auto-school-pg"
                key  = "PGPASSWORD"
              }
            }
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }
          env_from {
            secret_ref {
              name = "auto-school-pg"
            }
          }
          readiness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          liveness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"]
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { memory = "1Gi" }
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

resource "kubernetes_deployment_v1" "auto_school" {
  metadata {
    name      = "auto-school"
    namespace = var.namespace
    labels    = { app = "auto-school" }
  }
  spec {
    # Recreate: single replica on an RWO Longhorn PVC.
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "auto-school" }
    }
    template {
      metadata {
        labels = { app = "auto-school" }
      }
      spec {
        automount_service_account_token = false # matches live
        enable_service_links            = false
        node_selector = {
          "kubernetes.io/hostname" = "k3s-worker-02"
        }
        image_pull_secrets {
          name = "reg-credentials-ghcr"
        }
        host_aliases {
          ip        = "192.168.10.170"
          hostnames = ["firecrawl.vanderloch.com"]
        }
        security_context {
          run_as_user  = 1000
          run_as_group = 1000
          fs_group     = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        termination_grace_period_seconds = 120
        container {
          name              = "auto-school"
          image             = "ghcr.io/lochis/auto-school:latest" # own image, renovate-disabled
          image_pull_policy = "Always"
          port {
            name           = "ctrl"
            container_port = 7800
          }
          env {
            name  = "TZ"
            value = "America/Toronto"
          }
          env {
            name  = "REBUILD_AT"
            value = "07:00,19:00"
          }
          env {
            name  = "PGHOST"
            value = "auto-school-pg"
          }
          env {
            name  = "PGPORT"
            value = "5432"
          }
          env {
            name  = "PGDATABASE"
            value = "autoschool"
          }
          env {
            name  = "SMOKE_OWNER_UUID"
            value = "00000000-0000-4000-8000-000000000002"
          }
          env_from {
            secret_ref {
              name = "auto-school-env"
            }
          }
          env_from {
            secret_ref {
              name = "auto-school-pg"
            }
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = "ctrl"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = "ctrl"
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
          resources {
            requests = { cpu = "500m", memory = "1Gi" }
            limits   = { cpu = "4", memory = "4Gi" }
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          volume_mount {
            name       = "shm"
            mount_path = "/dev/shm"
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.data.metadata[0].name
          }
        }
        volume {
          name = "shm"
          empty_dir {
            medium     = "Memory"
            size_limit = "1Gi"
          }
        }
      }
    }
  }
  lifecycle {
    # kubectl set image / rollout restart flow: change-cause + restartedAt
    # annotations are runtime bookkeeping, not desired state.
    ignore_changes = [metadata[0].annotations, spec[0].template[0].metadata[0].annotations]
  }
}

# -----------------------------------------------------------------------------
# Frontend (2026-10-30 consolidation): was a sidecar in the backend pod, then
# briefly a stray live deployment (auto-school-platform). Now its own deploy
# carrying the union env — web + authentik + recorder/ingest tokens + AI keys
# (via auto-school-env secretKeyRefs). Handles school.vanderloch.com traffic
# AND the recorder heartbeat / ingest paths (tokens land here).
# -----------------------------------------------------------------------------
resource "kubernetes_deployment_v1" "auto_school_frontend" {
  metadata {
    name      = "auto-school-frontend"
    namespace = var.namespace
    labels    = { app = "auto-school-frontend" }
  }
  spec {
    # Single replica; mounts the shared RWO data PVC read-only alongside the
    # backend + recorder (co-scheduled on worker-02 via node_selector).
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "auto-school-frontend" }
    }
    template {
      metadata {
        labels = { app = "auto-school-frontend" }
      }
      spec {
        automount_service_account_token = false
        enable_service_links            = false
        node_selector = {
          "kubernetes.io/hostname" = "k3s-worker-02"
        }
        image_pull_secrets {
          name = "reg-credentials-ghcr"
        }
        security_context {
          run_as_user  = 1000
          run_as_group = 1000
          fs_group     = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name              = "frontend"
          image             = "ghcr.io/lochis/auto-school-frontend:latest" # own image, renovate-disabled
          image_pull_policy = "Always"
          port {
            name           = "http"
            container_port = 3000
          }
          env {
            name  = "AUTO_SCHOOL_DATA"
            value = "/data"
          }
          env {
            name  = "BACKEND_URL"
            value = "http://auto-school-ctrl:7800"
          }
          env {
            name  = "TZ"
            value = "America/Toronto"
          }
          env {
            name  = "TRUST_AUTHENTIK_HEADERS"
            value = "1"
          }
          env {
            name  = "AUTHENTIK_ADMIN_GROUP"
            value = "auto-school-admins"
          }
          env {
            name  = "AUTHENTIK_API_URL"
            value = "http://authentik-server.authentik.svc.cluster.local"
          }
          env {
            name = "AUTHENTIK_API_TOKEN"
            value_from {
              secret_key_ref {
                name     = "auto-school-env"
                key      = "AUTHENTIK_API_TOKEN"
                optional = true
              }
            }
          }
          env {
            name = "EDGE_SECRET"
            value_from {
              secret_key_ref {
                name     = "auto-school-env"
                key      = "EDGE_SECRET"
                optional = true
              }
            }
          }
          env {
            name = "RECORDER_TOKEN"
            value_from {
              secret_key_ref {
                name     = "auto-school-env"
                key      = "RECORDER_TOKEN"
                optional = true
              }
            }
          }
          env {
            name = "INGEST_TOKEN"
            value_from {
              secret_key_ref {
                name     = "auto-school-env"
                key      = "INGEST_TOKEN"
                optional = true
              }
            }
          }
          env {
            name  = "DB_READS"
            value = "1"
          }
          env {
            name  = "PLATFORM_AI"
            value = "1"
          }
          env {
            name = "GEMINI_API_KEY"
            value_from {
              secret_key_ref {
                name     = "auto-school-env"
                key      = "GEMINI_API_KEY"
                optional = true
              }
            }
          }
          env {
            name = "GLM_API_KEY"
            value_from {
              secret_key_ref {
                name     = "auto-school-env"
                key      = "GLM_API_KEY"
                optional = true
              }
            }
          }
          env {
            name  = "PGHOST"
            value = "auto-school-pg"
          }
          env {
            name  = "PGPORT"
            value = "5432"
          }
          env {
            name  = "PGDATABASE"
            value = "autoschool"
          }
          env_from {
            secret_ref {
              name = "auto-school-pg"
            }
          }
          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            period_seconds = 15
          }
          liveness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            period_seconds = 30
          }
          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
            read_only  = true
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.data.metadata[0].name
          }
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations, spec[0].template[0].metadata[0].annotations]
  }
}

# -----------------------------------------------------------------------------
# Recorder daemon (2026-10-30 consolidation): transcribed from the live
# deployment created during the recorder cutover (2026-10-29). Same image as
# the backend, run as a daemon; shares the RWO data PVC (co-scheduled on
# worker-02). Heartbeats to the frontend (auto-school:80) with RECORDER_TOKEN.
# -----------------------------------------------------------------------------
resource "kubernetes_deployment_v1" "auto_school_recorder" {
  metadata {
    name      = "auto-school-recorder"
    namespace = var.namespace
    labels    = { app = "auto-school-recorder" }
  }
  spec {
    # Single replica on the shared RWO PVC — kill-then-create.
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "auto-school-recorder" }
    }
    template {
      metadata {
        labels = { app = "auto-school-recorder" }
      }
      spec {
        automount_service_account_token = false
        enable_service_links            = false
        node_selector = {
          "kubernetes.io/hostname" = "k3s-worker-02"
        }
        image_pull_secrets {
          name = "reg-credentials-ghcr"
        }
        security_context {
          run_as_user  = 1000
          run_as_group = 1000
          fs_group     = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        termination_grace_period_seconds = 120
        container {
          name              = "auto-school"
          image             = "ghcr.io/lochis/auto-school:latest" # own image, renovate-disabled
          image_pull_policy = "Always"
          port {
            name           = "ctrl"
            container_port = 7800
          }
          env {
            name  = "TZ"
            value = "America/Toronto"
          }
          env {
            name  = "REBUILD_AT"
            value = "07:00,19:00"
          }
          env {
            name  = "PGHOST"
            value = "auto-school-pg"
          }
          env {
            name  = "PGPORT"
            value = "5432"
          }
          env {
            name  = "PGDATABASE"
            value = "autoschool"
          }
          env {
            name = "EDGE_SECRET"
            value_from {
              secret_key_ref {
                name     = "auto-school-env"
                key      = "EDGE_SECRET"
                optional = true
              }
            }
          }
          env {
            name  = "PLATFORM_URL"
            value = "http://auto-school:80"
          }
          env {
            name  = "RECORDER_ENDPOINT"
            value = "http://auto-school-recorder:7800"
          }
          env {
            name = "RECORDER_TOKEN"
            value_from {
              secret_key_ref {
                name     = "auto-school-env"
                key      = "RECORDER_TOKEN"
                optional = true
              }
            }
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = "ctrl"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = "ctrl"
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
          resources {
            requests = { cpu = "500m", memory = "1Gi" }
            limits   = { cpu = "4", memory = "4Gi" }
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          volume_mount {
            name       = "shm"
            mount_path = "/dev/shm"
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.data.metadata[0].name
          }
        }
        volume {
          name = "shm"
          empty_dir {
            medium     = "Memory"
            size_limit = "1Gi"
          }
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations, spec[0].template[0].metadata[0].annotations]
  }
}

resource "kubernetes_service_v1" "auto_school" {
  metadata {
    name      = "auto-school"
    namespace = var.namespace
    labels    = { app = "auto-school" }
  }
  spec {
    # Consolidation: :80 terminates on the FRONTEND pod (web + ingest +
    # recorder-heartbeat token check). Backend API lives on auto-school-ctrl.
    selector = { app = "auto-school-frontend" }
    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_service_v1" "auto_school_recorder" {
  metadata {
    name      = "auto-school-recorder"
    namespace = var.namespace
    labels    = { app = "auto-school-recorder" }
  }
  spec {
    selector = { app = "auto-school-recorder" }
    port {
      name        = "ctrl"
      port        = 7800
      target_port = "ctrl"
    }
  }
}

resource "kubernetes_service_v1" "auto_school_ctrl" {
  metadata {
    name      = "auto-school-ctrl"
    namespace = var.namespace
    labels    = { app = "auto-school" }
  }
  spec {
    selector = { app = "auto-school" }
    port {
      name        = "ctrl"
      port        = 7800
      target_port = "ctrl"
    }
  }
}

resource "kubernetes_service_v1" "auto_school_pg" {
  metadata {
    name      = "auto-school-pg"
    namespace = var.namespace
    labels    = { app = "auto-school-pg" }
  }
  spec {
    selector = { app = "auto-school-pg" }
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# ExternalName alias for the authentik embedded outpost (kept from live).
resource "kubernetes_service_v1" "authentik_outpost" {
  metadata {
    name      = "authentik-outpost"
    namespace = var.namespace
  }
  spec {
    type          = "ExternalName"
    external_name = "authentik-server.authentik.svc.cluster.local"
    port {
      name        = "http"
      port        = 80
      target_port = 80
    }
  }
}
