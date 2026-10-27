variable "namespace"        { type = string }
variable "osu_mongodb_uri" {
  type      = string
  sensitive = true
}
variable "osu_client_secret" {
  type      = string
  sensitive = true
}
variable "osu_session_secret" {
  type      = string
  sensitive = true
}

locals {
  base_url = "https://osutracker.vanderloch.com:2460"
}

resource "kubernetes_deployment_v1" "osu_tracker" {
  metadata {
    name      = "osu-tracker"
    namespace = var.namespace
    labels    = { app = "osu-tracker" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "osu-tracker" }
    }
    template {
      metadata {
        labels = { app = "osu-tracker" }
      }
      spec {
        container {
          name            = "osu-tracker"
          image           = "ghcr.io/lochis/osu-progress-tracker:latest"
          image_pull_policy = "Always"
          port {
            container_port = 3000
          }
          env {
            name  = "MONGODB_URI"
            value = var.osu_mongodb_uri
          }
          env {
            name  = "OSU_CLIENT_ID"
            value = "66731"
          }
          env {
            name  = "OSU_CLIENT_SECRET"
            value = var.osu_client_secret
          }
          env {
            name  = "SYNC_SECRET"
            value = var.osu_session_secret
          }
          env {
            name  = "OSU_REDIRECT_URI"
            value = "${local.base_url}/auth/callback"
          }
          env {
            name  = "SESSION_SECRET"
            value = var.osu_session_secret
          }
          env {
            name  = "APP_BASE_URL"
            value = local.base_url
          }
          env {
            name  = "SESSION_COOKIE_SECURE"
            value = "false"
          }
          env {
            name  = "ADMIN_OSU_IDS"
            value = "3420218"
          }
          readiness_probe {
            http_get {
              path = "/"
              port = 3000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
        image_pull_secrets {
          name = "reg-credentials-ghcr"
        }
      }
    }
  }
}

# MetalLB LoadBalancer — LB IP + nodePort are controller-allocated, and both
# Rancher (publicEndpoints) and MetalLB (pool) maintain annotations on this
# object, so the whole annotations map is ignored (same as namespaces).
resource "kubernetes_service_v1" "osu_tracker_svc" {
  metadata {
    name      = "osu-tracker-svc"
    namespace = var.namespace
  }
  spec {
    type     = "LoadBalancer"
    selector = { app = "osu-tracker" }
    port {
      name        = "http"
      port        = 2460
      target_port = 3000
    }
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

# Nudges the app's /api/sync/all every 30 min; authenticates with the same
# secret the app serves (osu_session_secret).
#
# NOTE: kubernetes_manifest, NOT kubernetes_cron_job_v1 — the typed resource
# forces replacement on every plan (provider defaults completions/parallelism
# to 1 against the API's nil; known provider bug). Raw manifest = no churn.
resource "kubernetes_manifest" "osu_tracker_sync" {
  manifest = {
    apiVersion = "batch/v1"
    kind       = "CronJob"
    metadata = {
      name      = "osu-tracker-sync"
      namespace = var.namespace
    }
    spec = {
      schedule                = "*/30 * * * *"
      concurrencyPolicy       = "Forbid"
      failedJobsHistoryLimit  = 3
      successfulJobsHistoryLimit = 1
      jobTemplate = {
        spec = {
          backoffLimit = 1
          template = {
            spec = {
              restartPolicy = "Never"
              containers = [{
                name            = "sync"
                image           = "curlimages/curl:8.16.0"
                imagePullPolicy = "Always"
                args = [
                  "-sS", "-X", "POST",
                  "-H", "x-sync-secret: ${var.osu_session_secret}",
                  "http://osu-tracker-svc.osu-tracker.svc.cluster.local:2460/api/sync/all",
                ]
              }]
            }
          }
        }
      }
    }
  }
}
