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
      magic_dns: true
      base_domain: headscale.internal
      nameservers:
        global:
          - 192.168.10.166
          - 1.1.1.1
        split:
          # tailnet-only zone: Pi-hole answers when up; 1.1.1.1 as second
          # resolver keeps PUBLIC records under vanderloch.com (auth/school/
          # headscale — used outbound by tailnet clients) resolvable if
          # Pi-hole is down. Without the split, a slow Pi-hole response makes
          # roaming clients fall back to 1.1.1.1, where the public zone
          # NXDOMAINs internal names (roam/ntfy/mattermost) — "offline" apps.
          vanderloch.com:
            - 192.168.10.166
            - 1.1.1.1
      search_domains:
        - vanderloch.com
      # MagicDNS local records — tailscaled answers these itself (100.100.100.100),
      # so tailnet-only names resolve even when Pi-hole is unreachable over the
      # tunnel (phones on cellular: 2026-11-23 roam/ntfy/mattermost "offline").
      # MIRROR of pihole_local_dns in terraform/platform/variables.tf — keep in
      # sync when adding hosts there. Pi-hole stays authoritative for names not
      # listed here (and for LAN clients, which never query these).
      extra_records:
        - { name: "pihole.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "pelican.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "traefik.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "homepage.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "jackett.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "wyze.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "pterodactyl.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "headscaleconsole.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "kubero.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "registry.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "registry.kubero.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "n8n.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "ha.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "firecrawl.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "headscale.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "roam.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "ntfy.vanderloch.com", type: A, value: "192.168.10.170" }
        - { name: "mattermost.vanderloch.com", type: A, value: "192.168.10.170" }

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
      "controlUrl": "https://headscale.vanderloch.com:2459"
    }
  EOT
  }
}
