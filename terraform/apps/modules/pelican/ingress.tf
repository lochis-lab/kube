resource "kubernetes_manifest" "pelican_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "pelican"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind     = "Rule"
        match    = "Host(`pelican.vanderloch.com`)"
        services = [{ name = "panel", port = 80, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
