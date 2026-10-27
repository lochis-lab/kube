resource "kubernetes_manifest" "ha_ir" {
  field_manager {
    force_conflicts = true # portainer manager also claims fields on this object
  }
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "homeassistant"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind  = "Rule"
        match = "Host(`ha.vanderloch.com`)"
        services = [{ name = "ha-svc", port = 8123, scheme = "http" }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
