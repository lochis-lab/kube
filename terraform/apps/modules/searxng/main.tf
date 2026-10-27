variable "namespace" { type = string }
variable "searxng_secret" {
  type      = string
  sensitive = true
}
variable "webshare_proxy_url" {
  type      = string
  sensitive = true
}

resource "kubernetes_config_map_v1" "settings" {
  metadata {
      name = "searxng-settings"
      namespace = var.namespace
    }
  data = { "settings.yml" = <<-EOT
    use_default_settings:
      engines:
        keep_only:
          - bing          # works via datacenter IPs (verified 200)
          - google        # 302s but usually parseable; drop if captcha-y
          - mojeek        # crawler-owned index, proxy-friendly
          - wikipedia     # if still timing out via proxy, remove this line
    # default search category is "web" in this SearXNG version but the kept
    # engines are tagged "general" only -> zero engines -> empty results.
    # Re-tag into both:
    engines:
      - name: bing
        disabled: false   # listed engines default to disabled — must flip
        categories: [general, web]
      - name: google
        disabled: false
        categories: [general, web]
      - name: mojeek
        disabled: false
        categories: [general, web]
      - name: wikipedia
        disabled: false
        categories: [general, web]
    server:
      secret_key: "${var.searxng_secret}"
      limiter: false            # cluster-internal; no bot protection needed
      image_proxy: false
    search:
      formats:
        - html
        - json                  # REQUIRED for Firecrawl (disabled by default)
      safe_search: 0
      autocomplete: ""
    # Route ALL engine queries through webshare (CONNECT verified; rotating
    # gateway -> new exit IP per engine request).
    outgoing:
      proxies:
        all://:
          - ${var.webshare_proxy_url}
    # searxng sends its own UA per engine by default; engines accept it.
  EOT
  }
}

resource "kubernetes_deployment_v1" "searxng" {
  metadata {
    name      = "searxng"
    namespace = var.namespace
    labels    = { app = "searxng" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "searxng" } }
    template {
      metadata { labels = { app = "searxng" } }
      spec {
        container {
          name  = "searxng"
          image = "docker.io/searxng/searxng@sha256:23482d8ecf7ddf66029479468ea04c1bb11d2b65785a17a7e629e2ffd13296ca"
          env {
      name = "SEARXNG_BASE_URL"
      value = "http://searxng.searxng.svc:8080/"
    }
          port {
      container_port = 8080
    }
          volume_mount {
            name       = "settings"
            mount_path = "/etc/searxng/settings.yml"
            sub_path   = "settings.yml"
          }
          readiness_probe {
            http_get {
      path = "/healthz"
      port = 8080
    }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
          liveness_probe {
            http_get {
      path = "/healthz"
      port = 8080
    }
            initial_delay_seconds = 30
            period_seconds        = 30
          }
          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
        volume {
          name = "settings"
          config_map {
      name = kubernetes_config_map_v1.settings.metadata[0].name
    }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "searxng" {
  metadata {
      name = "searxng"
      namespace = var.namespace
    }
  spec {
    selector = { app = "searxng" }
    port {
      port = 8080
      target_port = 8080
    }
  }
}
