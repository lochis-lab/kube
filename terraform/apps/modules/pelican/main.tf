variable "namespace" { type = string }

# Pelican Panel — new deployment, runs BESIDE pterodactyl (ns pterodactyl stays
# live and untouched). Reason for a separate DB server: Pelican requires
# MariaDB 10.11+ while the pterodactyl DB is 10.5, and Pelican's migration is an
# in-place schema upgrade that Pterodactyl cannot read afterwards.
#
# Creds live in the unmanaged Secret `pelican-secret` (ns pelican), created
# out-of-band (dealchis pattern) — secretKeyRef only, nothing inline:
#   DB_ROOT_PASSWORD, DB_PASSWORD, APP_KEY (copied from pterodactyl /app/var/.env)

resource "kubernetes_persistent_volume_claim_v1" "db_data" {
  metadata {
    name      = "pelican-db-pvc"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "20Gi" } # matches pterodactyl-db-pvc (source size)
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "panel_data" {
  metadata {
    name      = "pelican-data-pvc"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "10Gi" } # .env/APP_KEY, avatars, plugins, logs
    }
  }
}

# --- MariaDB 10.11 (Pelican minimum; pterodactyl's 10.5 is too old) ---------
resource "kubernetes_deployment_v1" "db" {
  metadata {
    name      = "db"
    namespace = var.namespace
    labels    = { app = "db" }
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate" # RWO PVC — RollingUpdate deadlocks on multi-attach
    }
    selector {
      match_labels = { app = "db" }
    }
    template {
      metadata {
        labels = { app = "db" }
      }
      spec {
        automount_service_account_token = false
        enable_service_links            = false
        container {
          name  = "db"
          image = "docker.io/library/mariadb:10.11" # major pinned (db-major strategy)
          port {
            container_port = 3306
          }
          env {
            name = "MARIADB_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = "pelican-secret"
                key  = "DB_ROOT_PASSWORD"
              }
            }
          }
          env {
            name  = "MARIADB_DATABASE"
            value = "pelican"
          }
          env {
            name  = "MARIADB_USER"
            value = "pelican"
          }
          env {
            name = "MARIADB_PASSWORD"
            value_from {
              secret_key_ref {
                name = "pelican-secret"
                key  = "DB_PASSWORD"
              }
            }
          }
          readiness_probe {
            exec {
              command = ["healthcheck.sh", "--connect", "--innodb_initialized"]
            }
            initial_delay_seconds = 15
            period_seconds        = 10
            timeout_seconds       = 5
          }
          liveness_probe {
            exec {
              command = ["healthcheck.sh", "--connect", "--innodb_initialized"]
            }
            initial_delay_seconds = 60
            period_seconds        = 30
            timeout_seconds       = 5
          }
          resources {
            requests = { cpu = "100m", memory = "512Mi" }
            limits   = { cpu = "1", memory = "1Gi" }
          }
          volume_mount {
            name       = "db-data"
            mount_path = "/var/lib/mysql"
          }
        }
        volume {
          name = "db-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.db_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "db" {
  metadata {
    name      = "db"
    namespace = var.namespace
    labels    = { app = "db" }
  }
  spec {
    selector = { app = "db" }
    port {
      port        = 3306
      target_port = 3306
    }
  }
}

# --- Panel ------------------------------------------------------------------
resource "kubernetes_deployment_v1" "panel" {
  metadata {
    name      = "panel"
    namespace = var.namespace
    labels    = { app = "panel" }
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate" # RWO PVC
    }
    selector {
      match_labels = { app = "panel" }
    }
    template {
      metadata {
        labels = { app = "panel" }
      }
      spec {
        automount_service_account_token = false
        enable_service_links            = false
        # /pelican-data is a Longhorn PVC (root:root). The panel runs as www-data
        # (uid 82) and storage/app/public is a symlink to /pelican-data/storage,
        # so Laravel cannot create its storage dirs without this.
        init_container {
          name              = "fix-perms"
          image             = "docker.io/library/busybox:1.37"
          image_pull_policy = "IfNotPresent"
          command = [
            "sh", "-c",
            "mkdir -p /pelican-data/storage/app /pelican-data/plugins /pelican-data/database && chown -R 82:82 /pelican-data",
          ]
          security_context {
            run_as_user = 0
          }
          volume_mount {
            name       = "pelican-data"
            mount_path = "/pelican-data"
          }
        }
        container {
          name = "panel"
          # beta image — digest-pinned; Renovate offers digest/tag bumps.
          image             = "ghcr.io/pelican/panel:v1.0.0-beta38"
          image_pull_policy = "IfNotPresent"
          port {
            name           = "http"
            container_port = 80
          }
          # entrypoint (APP_INSTALLED=true + non-sqlite DB) waits for the DB,
          # runs `php artisan migrate --force`, then starts supervisord:
          # php-fpm + caddy(:80) + queue worker + supercronic cron.
          env {
            name  = "XDG_DATA_HOME"
            value = "/pelican-data"
          }
          env {
            name  = "APP_ENV"
            value = "production"
          }
          env {
            name  = "APP_DEBUG"
            value = "false"
          }
          env {
            name  = "APP_URL"
            value = "https://pelican.vanderloch.com"
          }
          env {
            name  = "APP_TIMEZONE"
            value = "America/Toronto"
          }
          env {
            name  = "ADMIN_EMAIL"
            value = "lucas@vanderloch.com"
          }
          env {
            name  = "APP_INSTALLED"
            value = "true" # upgrade path: migrate the cloned Pterodactyl DB
          }
          env {
            name = "APP_KEY" # must be pterodactyl's key — decrypts 2FA secrets etc.
            value_from {
              secret_key_ref {
                name = "pelican-secret"
                key  = "APP_KEY"
              }
            }
          }
          env {
            name  = "BEHIND_PROXY"
            value = "true" # TLS terminated by traefik; listen :80, no LE
          }
          env {
            name  = "TRUSTED_PROXIES"
            value = "10.42.0.0/16" # cluster pod CIDR (traefik pods)
          }
          env {
            name  = "DB_CONNECTION"
            value = "mariadb" # without it Pelican falls back to SQLite
          }
          env {
            name  = "DB_HOST"
            value = "db.pelican.svc.cluster.local"
          }
          env {
            name  = "DB_PORT"
            value = "3306"
          }
          env {
            name  = "DB_DATABASE"
            value = "pelican"
          }
          env {
            name  = "DB_USERNAME"
            value = "pelican"
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = "pelican-secret"
                key  = "DB_PASSWORD"
              }
            }
          }
          env {
            name  = "SESSION_DRIVER"
            value = "database"
          }
          env {
            # file, not database: the cloned Pterodactyl DB has no `cache` table
            # and the panel reads the version cache before migrations run.
            name  = "CACHE_STORE"
            value = "file"
          }
          env {
            name  = "QUEUE_CONNECTION"
            value = "database"
          }
          # first boot migrates a full Pterodactyl DB — allow several minutes
          startup_probe {
            tcp_socket {
              port = 80
            }
            failure_threshold = 120
            period_seconds    = 5
          }
          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            period_seconds  = 10
            timeout_seconds = 5
          }
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 120
            period_seconds        = 30
            timeout_seconds       = 10
          }
          resources {
            requests = { cpu = "100m", memory = "512Mi" }
            limits   = { cpu = "1", memory = "1Gi" }
          }
          volume_mount {
            name       = "pelican-data"
            mount_path = "/pelican-data"
          }
          volume_mount {
            name       = "logs"
            mount_path = "/var/www/html/storage/logs"
          }
        }
        volume {
          name = "pelican-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.panel_data.metadata[0].name
          }
        }
        volume {
          name = "logs"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "panel" {
  metadata {
    name      = "panel"
    namespace = var.namespace
    labels    = { app = "panel" }
  }
  spec {
    selector = { app = "panel" }
    port {
      port        = 80
      target_port = 80
    }
  }
}
