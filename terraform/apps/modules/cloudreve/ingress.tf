resource "kubernetes_manifest" "cloudreve_ir" {
  field_manager {
    force_conflicts = true # portainer manager also claims fields on this object
  }
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "cloudreve-ingress"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["outbound2"]
      routes = [{
        kind     = "Rule"
        match    = "Host(`cloudreve.vanderloch.com`)"
        services = [{ name = "cloudreve-service", port = 80, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
