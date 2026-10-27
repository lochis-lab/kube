resource "kubernetes_manifest" "vocard_dashboard_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "vocard-dashboard"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["outbound"]
      routes = [{
        kind     = "Rule"
        match    = "Host(`spookic.vanderloch.com`)"
        services = [{ name = "vocard-dashboard", port = 8000, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}

resource "kubernetes_manifest" "vocard_dashboard_ipc_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "vocard-dashboard-ipc"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["outbound2"]
      routes = [{
        kind     = "Rule"
        match    = "Host(`spookic.vanderloch.com`)"
        services = [{ name = "vocard-dashboard", port = 2460, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
