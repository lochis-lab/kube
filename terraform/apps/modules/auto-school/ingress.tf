resource "kubernetes_manifest" "auto_school_ir" {
  # Live object gained fields from a manual kubectl patch during the recorder
  # cutover; TF is the owner of record — force SSA conflicts instead of erroring.
  field_manager {
    name            = "terraform-apps"
    force_conflicts = true
  }
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
        # bypass route (matches live since the 2026-10 recorder cutover):
        # session-ingest + recorder-heartbeat must skip authentik — headless
        # recorders can't complete the forwardauth flow. priority pinned to 100
        # (live drift guard): keep the explicit value so TF applies don't strip
        # it down to Traefik's auto-calculated priority.
        {
          kind     = "Rule"
          match    = "Host(`school.vanderloch.com`) && (PathPrefix(`/api/ingest/session`) || PathPrefix(`/api/recorder/heartbeat`))"
          priority = 100
          services = [{
            name   = "auto-school"
            port   = 80
            scheme = "http"
          }]
        },
        {
          kind        = "Rule"
          match       = "Host(`school.vanderloch.com`)"
          middlewares = [{ name = "authentik-forwardauth" }, { name = "auto-school-edge-marker" }]
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
