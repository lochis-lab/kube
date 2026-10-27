variable "namespace" { type = string }
variable "nfs_media_server" { type = string }

resource "kubernetes_persistent_volume_claim_v1" "postgres_data" {
  metadata {
    name      = "postgres-data"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "5Gi" } # immutable — matches live
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "redis_data" {
  metadata {
    name      = "redis-data"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = { storage = "1Gi" } # immutable — matches live
    }
  }
}

# cloudreve-config Secret stays unmanaged (dealchis pattern): all db/redis
# creds flow through secretKeyRef env below.

resource "kubernetes_deployment_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = var.namespace
    labels    = { app = "postgres" }
  }
  spec {
    # Recreate: single replica on RWO Longhorn PVC — a RollingUpdate surge pod
    # lands on another node and deadlocks on Multi-Attach.
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "postgres" }
    }
    template {
      metadata {
        labels = { app = "postgres" }
      }
      spec {
        container {
          name              = "postgres"
          image             = "docker.io/library/postgres:18-alpine"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 5432
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }
          env {
            name = "POSTGRES_DB"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "DB_NAME"
              }
            }
          }
          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "DB_USER"
              }
            }
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "DB_PASSWORD"
              }
            }
          }
          volume_mount {
            name       = "db-storage"
            mount_path = "/var/lib/postgresql/data"
          }
        }
        volume {
          name = "db-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.postgres_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = var.namespace
    labels    = { app = "redis" }
  }
  spec {
    # Recreate: single replica on RWO Longhorn PVC — a RollingUpdate surge pod
    # lands on another node and deadlocks on Multi-Attach.
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { app = "redis" }
    }
    template {
      metadata {
        labels = { app = "redis" }
      }
      spec {
        container {
          name              = "redis"
          image             = "docker.io/library/redis:7-alpine"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 6379
          }
          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "REDIS_PASSWORD"
              }
            }
          }
          volume_mount {
            name       = "redis-storage"
            mount_path = "/data"
          }
        }
        volume {
          name = "redis-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.redis_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "cloudreve" {
  metadata {
    name      = "cloudreve"
    namespace = var.namespace
    labels    = { app = "cloudreve" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "cloudreve" }
    }
    template {
      metadata {
        labels = { app = "cloudreve" }
      }
      spec {
        container {
          # rolling release — digest-pinned (searxng pattern, Renovate bumps digests)
          name              = "cloudreve"
          image             = "docker.io/cloudreve/cloudreve:latest@sha256:5c6c5baf7fa5bc6e1bb9a7509c09dde00e80b618d180244eb1d5f7e36b358ea2"
          image_pull_policy = "Always"
          port {
            name           = "http"
            container_port = 5212
          }
          port {
            name           = "aria2-tcp"
            container_port = 6888
            protocol       = "TCP"
          }
          port {
            name           = "aria2-udp"
            container_port = 6888
            protocol       = "UDP"
          }
          env {
            name = "CR_CONF_Database.Type"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "DB_TYPE"
              }
            }
          }
          env {
            name = "CR_CONF_Database.Host"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "DB_HOST"
              }
            }
          }
          env {
            name = "CR_CONF_Database.Port"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "DB_PORT"
              }
            }
          }
          env {
            name = "CR_CONF_Database.User"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "DB_USER"
              }
            }
          }
          env {
            name = "CR_CONF_Database.Password"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "DB_PASSWORD"
              }
            }
          }
          env {
            name = "CR_CONF_Database.Name"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "DB_NAME"
              }
            }
          }
          env {
            name = "CR_CONF_Redis.Server"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "REDIS_SERVER"
              }
            }
          }
          env {
            name = "CR_CONF_Redis.Password"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "REDIS_PASSWORD"
              }
            }
          }
          env {
            name = "CR_CONF_Redis.DB"
            value_from {
              secret_key_ref {
                name = "cloudreve-config"
                key  = "REDIS_DB"
              }
            }
          }
          volume_mount {
            name       = "data"
            mount_path = "/cloudreve/data"
          }
        }
        volume {
          name = "data"
          nfs {
            server    = var.nfs_media_server
            path      = "/srv/cloudreve"
            read_only = false
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "cloudreve_service" {
  metadata {
    name      = "cloudreve-service"
    namespace = var.namespace
  }
  spec {
    selector = { app = "cloudreve" }
    port {
      name        = "http"
      port        = 80
      target_port = 5212
    }
    port {
      name        = "aria2-tcp"
      protocol    = "TCP"
      port        = 6888
      target_port = 6888
    }
    port {
      name        = "aria2-udp"
      protocol    = "UDP"
      port        = 6888
      target_port = 6888
    }
  }
}

resource "kubernetes_service_v1" "postgres_service" {
  metadata {
    name      = "postgres-service"
    namespace = var.namespace
  }
  spec {
    selector = { app = "postgres" }
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

resource "kubernetes_service_v1" "redis_service" {
  metadata {
    name      = "redis-service"
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
