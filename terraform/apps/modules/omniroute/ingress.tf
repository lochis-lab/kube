resource "kubernetes_manifest" "omniroute_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "omniroute-ingress"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind     = "Rule"
        match    = "Host(`omniroute.vanderloch.com`)"
        services = [{ name = "omniroute-svc", port = 20128, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
