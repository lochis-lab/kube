resource "kubernetes_manifest" "n8n_ir" {
  field_manager {
    force_conflicts = true # portainer manager also claims fields on this object
  }
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "n8n"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind     = "Rule"
        match    = "Host(`n8n.vanderloch.com`)"
        services = [{ name = "n8n", port = 80, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
