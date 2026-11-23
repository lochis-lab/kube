# Mattermost — self-hosted Slack for the automation HQ. TAILNET/LAN-ONLY by
# design: IngressRoute on websecure :443 + Pi-hole local DNS, NO Cloudflare
# tunnel entry. First consumer: gmail-digest posts the daily card to
# #gmail-digest via incoming webhook. Bundled postgres (firecrawl pattern,
# but self-contained: random_password instead of a pre-existing secret).

variable "namespace" { type = string }

locals {
  mm_img = "mattermost/mattermost-team-edition:12.1" # renovate bumps
  pg_img = "postgres:16.16-alpine"                   # renovate bumps
}

resource "random_password" "pg" {
  length  = 24
  special = false
}

# --- postgres ---------------------------------------------------------------

resource "kubernetes_persistent_volume_claim_v1" "pgdata" {
  metadata {
    name      = "mattermost-pgdata"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "8Gi" }
    }
  }
}

resource "kubernetes_deployment_v1" "postgres" {
  metadata {
    name      = "mattermost-postgres"
    namespace = var.namespace
    labels    = { app = "mattermost-postgres" }
  }
  spec {
    replicas = 1
    strategy { type = "Recreate" } # RWO PVC
    selector {
      match_labels = { app = "mattermost-postgres" }
    }
    template {
      metadata { labels = { app = "mattermost-postgres" } }
      spec {
        container {
          name  = "postgres"
          image = local.pg_img
          port {
            container_port = 5432
          }
          env {
            name  = "POSTGRES_USER"
            value = "mattermost"
          }
          env {
            name  = "POSTGRES_PASSWORD"
            value = random_password.pg.result
          }
          env {
            name  = "POSTGRES_DB"
            value = "mattermost"
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }
          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "mattermost"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              memory = "512Mi"
            }
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

resource "kubernetes_service_v1" "postgres" {
  metadata {
    name      = "mattermost-postgres"
    namespace = var.namespace
  }
  spec {
    selector = { app = "mattermost-postgres" }
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# --- mattermost --------------------------------------------------------------

resource "kubernetes_persistent_volume_claim_v1" "data" {
  metadata {
    name      = "mattermost-data"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "5Gi" }
    }
  }
}

resource "kubernetes_deployment_v1" "mattermost" {
  metadata {
    name      = "mattermost"
    namespace = var.namespace
    labels    = { app = "mattermost" }
  }
  spec {
    replicas = 1
    strategy { type = "Recreate" } # RWO PVC
    selector {
      match_labels = { app = "mattermost" }
    }
    template {
      metadata { labels = { app = "mattermost" } }
      spec {
        # mattermost runs as UID 2000; fresh PVCs mount root-owned — without
        # fsGroup the pod crashloops on /mattermost/data writes.
        security_context {
          fs_group = 2000
        }
        container {
          name  = "mattermost"
          image = local.mm_img
          port {
            container_port = 8065
          }
          env {
            name  = "MM_SERVICESETTINGS_SITEURL"
            value = "https://mattermost.vanderloch.com"
          }
          env {
            name  = "MM_SQLSETTINGS_DRIVERNAME"
            value = "postgres"
          }
          env {
            name  = "MM_SQLSETTINGS_DATASOURCE"
            value = "postgres://mattermost:${random_password.pg.result}@${kubernetes_service_v1.postgres.metadata[0].name}:5432/mattermost?sslmode=disable"
          }
          env {
            # keep config.json on the data PVC so System Console changes survive
            name  = "MM_CONFIG"
            value = "/mattermost/data/config.json"
          }
          env {
            # gmail-digest interactive buttons: click callbacks go to the
            # cleanup hook on happy-agent-01's tailscale IP — an internal
            # connection, which Mattermost refuses to call unless whitelisted.
            name  = "MM_SERVICESETTINGS_ALLOWEDUNTRUSTEDINTERNALCONNECTIONS"
            value = "100.64.0.0/10,127.0.0.1"
          }
          readiness_probe {
            http_get {
              path = "/api/v4/system/ping"
              port = 8065
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }
          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              memory = "1Gi"
            }
          }
          volume_mount {
            name       = "data"
            mount_path = "/mattermost/data"
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
}

resource "kubernetes_service_v1" "mattermost" {
  metadata {
    name      = "mattermost"
    namespace = var.namespace
  }
  spec {
    selector = { app = "mattermost" }
    port {
      port        = 8065
      target_port = 8065
    }
  }
}
