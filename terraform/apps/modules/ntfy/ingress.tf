resource "kubernetes_manifest" "ntfy_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "ntfy"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class"             = "traefik-external"
        "traefik.ingress.kubernetes.io/websocket" = "true" # web app live stream
      }
    }
    spec = {
      entryPoints = ["websecure"] # tailnet-only: 443, no tunnel/2459
      routes = [{
        kind  = "Rule"
        match = "Host(`ntfy.vanderloch.com`)"
        services = [{
          name = kubernetes_service_v1.ntfy.metadata[0].name
          port = 80
        }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
