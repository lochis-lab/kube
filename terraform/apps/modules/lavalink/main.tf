# lavalink — moved from ns default (portainer stack 363) to ns vocard.
# Live consumer: the vocard-dashboard web player (lavalink logs show Client
# [WEB]); its configured address is unknown (not in env/secret/filesystem —
# likely Atlas-stored or compiled default), so continuity is guaranteed three
# ways: same VIP 192.168.10.163, same port 2333, and an ExternalName alias at
# the old DNS name. Config carried verbatim from the old lavalink-config CM
# except the four templated secrets.
variable "namespace" {
  type = string
}

variable "password" {
  type      = string
  sensitive = true
}

variable "spotify_client_id" {
  type      = string
  sensitive = true
}

variable "spotify_client_secret" {
  type      = string
  sensitive = true
}

variable "yt_oauth_refresh_token" {
  type      = string
  sensitive = true
}

resource "kubernetes_config_map_v1" "lavalink_config" {
  metadata {
    name      = "lavalink-config"
    namespace = var.namespace
  }
  data = {
    "application.yml" = <<-EOT
    server:
      port: 8080
      address: 0.0.0.0

    lavalink:
      server:
        password: "${var.password}"
        sources:
          youtube: false
          soundcloud: false

      plugins:
        - dependency: "dev.lavalink.youtube:youtube-plugin:2be8e542d3f6f178e048dca565892684c2e40177"
          snapshot: true
        - dependency: "com.github.topi314.lavasrc:lavasrc-plugin:4.8.3"
        - dependency: "com.github.Lochis.soundy:plugin:1.1.0"
          repository: "https://jitpack.io"

      logging:
         level:
           dev.lavalink.youtube.http.YoutubeOauth2Handler: INFO

    plugins:

      lavasrc:
        providers:
          - "ytsearch:%ISRC%"
          - "ytsearch:%QUERY%"
        sources:
          spotify: true
        spotify:
          clientId: "${var.spotify_client_id}"
          clientSecret: "${var.spotify_client_secret}"
          countryCode: "CA"
      youtube:
        enabled: true
        allowSearch: true
        allowDirectVideoIds: true
        allowDirectPlaylistIds: true
        clients:
          - TVHTML5_SIMPLY
          - TV
          - MUSIC
          - ANDROID_VR
          - WEB
          - WEBEMBEDDED
        oauth:
          enabled: true
          refreshToken: "${var.yt_oauth_refresh_token}"
        remoteCipher:
          url: "https://cipher.kikkia.dev/"
          userAgent: "vocard-lavalink"
    EOT
  }
}

resource "kubernetes_deployment_v1" "lavalink" {
  metadata {
    name      = "lavalink"
    namespace = var.namespace
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "lavalink" }
    }
    template {
      metadata {
        labels = { app = "lavalink" }
      }
      spec {
        container {
          name            = "lavalink"
          image           = "ghcr.io/lavalink-devs/lavalink:4.2.2"
          image_pull_policy = "Always"
          port {
            container_port = 8080
          }
          env {
            name  = "LAVALINK_SERVER_PASSWORD"
            value = var.password
          }
          resources {
            requests = { memory = "264Mi" }
            limits   = { memory = "512Mi" }
          }
          volume_mount {
            name       = "lavalink-config"
            mount_path = "/opt/Lavalink/application.yml"
            sub_path   = "application.yml"
          }
        }
        volume {
          name = "lavalink-config"
          config_map {
            name = kubernetes_config_map_v1.lavalink_config.metadata[0].name
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations] # k3s/metallb re-add theirs every apply
  }
}

resource "kubernetes_service_v1" "lavalink" {
  metadata {
    name      = "lavalink"
    namespace = var.namespace
  }
  spec {
    type                   = "LoadBalancer"
    load_balancer_ip       = "192.168.10.163" # same VIP the old default-ns svc held
    external_traffic_policy = "Cluster"
    selector               = { app = "lavalink" }
    port {
      port        = 2333
      target_port = 8080
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations] # k3s/metallb re-add theirs every apply
  }
}

# Compatibility alias for anything still dialing the old in-cluster DNS name
# (lavalink.default.svc.cluster.local) — delete once the dashboard's lavalink
# address is confirmed repointed at lavalink.vocard.svc.
resource "kubernetes_service_v1" "lavalink_default_alias" {
  metadata {
    name      = "lavalink"
    namespace = "default"
  }
  spec {
    type          = "ExternalName"
    external_name = "lavalink.vocard.svc.cluster.local"
  }
}
