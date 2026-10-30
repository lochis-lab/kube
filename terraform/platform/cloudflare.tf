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
    ingress = [
      { hostname = "osutracker.vanderloch.com",
        service  = "https://traefik.traefik.svc.cluster.local:2460",
        origin_request = {
          # SNI would default to the service hostname (traefik.traefik.svc…),
          # which doesn't match the *.vanderloch.com cert traefik serves
          # (x509 hostname mismatch → 502). Pin SNI to the public host.
          origin_server_name = "osutracker.vanderloch.com"
        } },
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
    image        = { tag = "2026.10.7" }   # chart default is 'latest' — pin it
    cloudflare   = {
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
  ttl     = 1      # 1 = 'automatic' (proxied records are Auto anyway)
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
