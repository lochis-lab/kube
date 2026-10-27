resource "kubernetes_manifest" "paloch_web_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "paloch-web"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class"             = "traefik-external"
        "traefik.ingress.kubernetes.io/websocket" = "true"
      }
    }
    spec = {
      entryPoints = ["outbound2"]
      routes = [{
        kind     = "Rule"
        match    = "Host(`paloch.vanderloch.com`)"
        services = [{ name = "paloch-web-service", port = 3000, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
