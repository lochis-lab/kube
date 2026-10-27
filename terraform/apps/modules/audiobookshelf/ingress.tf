
resource "kubernetes_manifest" "audiobookshelf_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "audiobookshelf"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class"                    = "traefik-external"
        "traefik.ingress.kubernetes.io/websocket"        = "true"
      }
    }
    spec = {
      entryPoints = ["outbound"]
      routes = [{
        kind  = "Rule"
        match = "Host(`abs.vanderloch.com`)"
        services = [{ name = "audiobookshelf", port = 2459, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}

resource "kubernetes_manifest" "audiobookshelf_ws_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "audiobookshelf-ws"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class"                    = "traefik-external"
        "traefik.ingress.kubernetes.io/websocket"        = "true"
      }
    }
    spec = {
      entryPoints = ["outbound2"]
      routes = [{
        kind  = "Rule"
        match = "Host(`abs.vanderloch.com`)"
        services = [{ name = "audiobookshelf", port = 2460, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
