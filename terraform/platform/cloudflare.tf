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
        service  = "https://traefik.traefik.svc.cluster.local:2460" },
      { service = "http_status:404" }
    ]
  }
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
