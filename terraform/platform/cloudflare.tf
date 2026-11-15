resource "random_password" "tunnel_secret_seed" { length = 32 }

resource "cloudflare_zero_trust_tunnel_cloudflared" "lochis" {
  account_id    = var.cloudflare_account_id
  name          = "lochis-k3s"
  config_src    = "cloudflare"
  tunnel_secret = base64sha256(random_password.tunnel_secret_seed.result)
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "lochis" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.lochis.id

  config = {
    # move to have vanderloch.com as top level origin server name
    # ingresses don't have to necessarily match the TLS handshake that cloudflare tunnel does
    # vanderloch.com can do the handshake for aerosol.dev too
    origin_request = {
      origin_server_name = "vanderloch.com"
    }
    ingress = [
      { hostname = "osutracker.vanderloch.com", service = "https://traefik.traefik.svc.cluster.local:2460" },
      { hostname = "spookic.vanderloch.com", service = "https://traefik.traefik.svc.cluster.local:2459" },
      { hostname = "paloch.vanderloch.com", service = "https://traefik.traefik.svc.cluster.local:2460" },
      { hostname = "abs.vanderloch.com", service = "https://traefik.traefik.svc.cluster.local:2459" },
      { hostname = "school.vanderloch.com", service = "https://traefik.traefik.svc.cluster.local:2459" },

      { hostname = "qt-dev.aerosol.dev", service = "https://traefik.traefik.svc.cluster.local:2459" },
      { hostname = "quickticket.aerosol.dev", service = "https://traefik.traefik.svc.cluster.local:2459" },
      { service = "http_status:404" }
    ]
  }
}

# cloudflared connector for the remotely-managed tunnel. Ingress rules live in
# cloudflare_zero_trust_tunnel_cloudflared_config above; the chart only runs the
# daemon (it wraps the token into a Secret + rolls pods on token change).
resource "helm_release" "cloudflared" {
  name             = "cloudflared"
  namespace        = "cloudflare"
  create_namespace = true

  repository = "https://cloudflare.github.io/helm-charts"
  chart      = "cloudflare-tunnel-remote"
  version    = "0.1.2"

  values = [yamlencode({
    replicaCount = 2
    image        = { tag = "2026.10.7" } # chart default is 'latest' — pin it
    cloudflare = {
      tunnel_token = base64encode(jsonencode({
        a = cloudflare_zero_trust_tunnel_cloudflared.lochis.account_tag
        t = cloudflare_zero_trust_tunnel_cloudflared.lochis.id
        s = base64sha256(random_password.tunnel_secret_seed.result)
      }))
    }
  })]

  wait    = true
  timeout = 300
}

resource "cloudflare_dns_record" "osutracker" {
  zone_id = var.cloudflare_zone_id_vanderloch
  name    = "osutracker"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.lochis.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1 # 1 = 'automatic' (proxied records are Auto anyway)
  proxied = true
}

resource "cloudflare_dns_record" "spookic" {
  zone_id = var.cloudflare_zone_id_vanderloch
  name    = "spookic"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.lochis.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "paloch" {
  zone_id = var.cloudflare_zone_id_vanderloch
  name    = "paloch"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.lochis.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "abs" {
  zone_id = var.cloudflare_zone_id_vanderloch
  name    = "abs"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.lochis.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

# school (auto-school) — Cutover note: the zone currently has a GREY A record
# for `school` pointing at the WAN IP (direct :2459 DNAT). The CF API rejects
# creating this CNAME while that A record exists — delete the grey A in the
# dashboard FIRST, then `atlantis apply -p terraform-platform`. Rollback =
# delete this record + recreate the grey A (site serves on :2459 again).
# Ordering with the app: the IngressRoute already binds entrypoint `outbound`
# with the authentik forwardauth chain — unchanged by this PR (clerk flip is
# a later, separate change; see auto-school docs/planning/clerk-migration.md §9).
resource "cloudflare_dns_record" "school" {
  zone_id = var.cloudflare_zone_id_vanderloch
  name    = "school"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.lochis.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "qt-dev" {
  zone_id = var.cloudflare_zone_id_aerosol
  name    = "qt-dev"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.lochis.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "quickticket" {
  zone_id = var.cloudflare_zone_id_aerosol
  name    = "quickticket"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.lochis.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

output "tunnel_token" {
  # v5 provider dropped the `.token` attribute — the token is just base64 JSON
  # {a: account_tag, t: tunnel id, s: secret}; rebuild it from known values.
  value = base64encode(jsonencode({
    a = cloudflare_zero_trust_tunnel_cloudflared.lochis.account_tag
    t = cloudflare_zero_trust_tunnel_cloudflared.lochis.id
    s = base64sha256(random_password.tunnel_secret_seed.result)
  }))
  sensitive = true
}
