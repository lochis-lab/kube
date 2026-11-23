resource "kubernetes_manifest" "mattermost_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "mattermost"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class"             = "traefik-external"
        "traefik.ingress.kubernetes.io/websocket" = "true" # live updates
      }
    }
    spec = {
      entryPoints = ["websecure"] # tailnet-only: 443, no tunnel/2459
      routes = [{
        kind  = "Rule"
        match = "Host(`mattermost.vanderloch.com`)"
        services = [{
          name = kubernetes_service_v1.mattermost.metadata[0].name
          port = 8065
        }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
