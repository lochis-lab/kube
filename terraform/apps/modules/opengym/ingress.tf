# Clean-443 tunnel route (k3s revival shape): cloudflare tunnel ingress sends
# gym.vanderloch.com -> traefik outbound (2459); this route matches by Host
# and terminates the internal hop with the Reflector-copied wildcard cert.
# Passkeys require the exact HTTPS origin https://gym.vanderloch.com (no port).
resource "kubernetes_manifest" "opengym_ir" {
  field_manager {
    force_conflicts = true # portainer + our terraform-manager SSA both claim fields
  }
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "opengym-ingress"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["outbound"]
      routes = [{
        kind  = "Rule"
        match = "Host(`gym.vanderloch.com`)"
        services = [{ name = "opengym-svc", port = 80, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" } # copy lands via Reflector (platform/reflector.tf)
    }
  }
}
