# headscale config — verbatim from live headscale-config CM.
# NOTE: v0.23+ schema (headscale 0.28): override_local_dns is REMOVED (PR #2034)
# and its presence fatals config load. DNS uses search_domains instead.
resource "kubernetes_config_map_v1" "config" {
  metadata {
    name      = "headscale-config"
    namespace = var.namespace
  }
  data = { "config.yaml" = <<-EOT
    server_url: https://headscale.vanderloch.com:2459
    listen_addr: 0.0.0.0:8080
    metrics_listen_addr: 0.0.0.0:9090
    grpc_listen_addr: 0.0.0.0:50443
    grpc_allow_insecure: false

    private_key_path: /var/lib/headscale/private.key

    noise:
      private_key_path: /var/lib/headscale/noise_private.key

    prefixes:
      v4: 100.64.0.0/10
      v6: fd7a:115c:a1e0::/48
      allocation: sequential

    derp:
      urls:
        - https://controlplane.tailscale.com/derpmap/default
      server:
        enabled: false

    dns:
      magic_dns: false
      base_domain: headscale.internal
      nameservers:
        global:
          - 192.168.10.166
          - 1.1.1.1
      search_domains:
        - vanderloch.com

    database:
      type: sqlite3
      sqlite:
        path: /var/lib/headscale/db.sqlite

    log:
      format: text
      level: info
  EOT
  }
}

resource "kubernetes_config_map_v1" "console_config" {
  metadata {
    name      = "headscale-console-config"
    namespace = var.namespace
  }
  data = { "config.json" = <<-EOT
    {
      "logLevel": "INFO",
      "controlUrl": "https://headscaleconsole.vanderloch.com:2459",
      "selfserviceHostname": "headscale.vanderloch.com",
      "policyserviceHostname": "headscale.vanderloch.com",
      "serverSocket": "/var/run/headscale/headscale.sock"
    }
  EOT
  }
}
