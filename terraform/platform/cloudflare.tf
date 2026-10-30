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
  content = cloudflare_zero_trust_tunnel_cloudflared.lochis.cname
  type    = "CNAME"
  proxied = true
}

output "tunnel_token" {
  value     = cloudflare_zero_trust_tunnel_cloudflared.lochis.token
  sensitive = true
}
