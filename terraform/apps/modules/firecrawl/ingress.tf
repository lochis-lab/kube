resource "kubernetes_manifest" "firecrawl_ir" {
  field_manager {
    force_conflicts = true # portainer manager also claims fields on this object
  }
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "firecrawl"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind  = "Rule"
        match = "Host(`firecrawl.vanderloch.com`)"
        services = [{ name = "api", port = 3002, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
