resource "kubernetes_manifest" "auto_school_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "auto-school"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["outbound"]
      routes = [
        {
          kind  = "Rule"
          match = "Host(`school.vanderloch.com`) && PathPrefix(`/outpost.goauthentik.io/`)"
          services = [{
            name   = "ak-outpost-authentik-embedded-outpost.authentik.svc.cluster.local"
            port   = 9000
            scheme = "http"
          }]
        },
        {
          kind        = "Rule"
          match       = "Host(`school.vanderloch.com`)"
          middlewares = [{ name = "authentik-forwardauth" }]
          services = [{
            name   = "auto-school"
            port   = 80
            scheme = "http"
          }]
        },
      ]
      tls = { secretName = "lochis-tls" }
    }
  }
}
