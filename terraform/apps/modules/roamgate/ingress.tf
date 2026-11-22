resource "kubernetes_manifest" "roamgate_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "roamgate"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class"             = "traefik-external"
        "traefik.ingress.kubernetes.io/websocket" = "true" # terminal streaming
      }
    }
    spec = {
      entryPoints = ["websecure"] # tailscale-only: 443, no tunnel/2459
      routes = [{
        kind  = "Rule"
        match = "Host(`roam.vanderloch.com`)"
        services = [{
          name = kubernetes_service_v1.roamgate.metadata[0].name
          port = 8787
        }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
