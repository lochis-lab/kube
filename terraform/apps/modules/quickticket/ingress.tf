# TCP routes for the externally-hosted quickticket backend (dev), terminated
# at Traefik on the outbound entrypoint (:2459 DNAT). The original IRTCPs lived
# in the namespace and were lost with it (2026-10-28 cascade); these are
# reconstructions — TLS terminates at Traefik with the default cert (the
# backend services are plaintext; clients use sslmode=require / non-verifying
# TLS, which is how the originals worked).

resource "kubernetes_manifest" "postgres_dev_irtcp" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRouteTCP"
    metadata = {
      name      = "qt-postgres-dev-tcp"
      namespace = var.namespace
    }
    spec = {
      entryPoints = ["outbound"]
      routes = [{
        match = "HostSNI(`postgres-dev-qt.aerosol.dev`)"
        services = [{
          name = "quickticket-postgres-dev"
          port = 5432
        }]
      }]
      tls = { secretName = "aerosol-tls" } # valid *.aerosol.dev wildcard, Reflector-reflected into this ns
    }
  }
}

resource "kubernetes_manifest" "redis_dev_irtcp" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRouteTCP"
    metadata = {
      name      = "qt-redis-dev-tcp"
      namespace = var.namespace
    }
    spec = {
      entryPoints = ["outbound"]
      routes = [{
        match = "HostSNI(`redis-dev-qt.aerosol.dev`)"
        services = [{
          name = "quickticket-redis-dev"
          port = 6379
        }]
      }]
      tls = { secretName = "aerosol-tls" } # valid *.aerosol.dev wildcard, Reflector-reflected into this ns
    }
  }
}
