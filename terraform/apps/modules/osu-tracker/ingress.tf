resource "kubernetes_manifest" "osu_tracker_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "osu-tracker-ingress"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["outbound2"]
      routes = [{
        kind  = "Rule"
        match = "Host(`osutracker.vanderloch.com`)"
        services = [{ name = "osu-tracker-svc", port = 2460, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
