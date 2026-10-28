# TCP routes for the externally-hosted quickticket backend (dev), terminated
# at Traefik on the outbound entrypoint (:2459 DNAT). The original IRTCPs lived
# in the namespace and were lost with it (2026-10-28 cascade); these are
# reconstructions — TLS terminates at Traefik with the default cert (the
# backend services are plaintext; clients use sslmode=require / non-verifying
# TLS, which is how the originals worked).

# TLSOption accepting libpq's ALPN offer. libpq >= 17 always advertises
# "postgresql" in the ClientHello; Traefik's TLS terminator rejects unknown
# ALPN with `no_application_protocol` unless a TLSOption lists it. The
# original stack had exactly this (user: "it was some middleware, some alpn
# or something") — it died with the ns and is reconstructed here. Clients
# that offer no ALPN (DBeaver/pgjdbc, openssl, redis-py) are unaffected.

resource "kubernetes_manifest" "postgres_alpn_tlsoption" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "TLSOption"
    metadata = {
      name      = "quickticket-alpn"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      alpnProtocols = ["postgresql"]
    }
  }
}

resource "kubernetes_manifest" "postgres_dev_irtcp" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRouteTCP"
    metadata = {
      name      = "quickticket-postgres-dev"
      namespace = var.namespace
      annotations = {
        # traefik's CRD provider only watches resources with this class
        "kubernetes.io/ingress.class" = "traefik-external"
      }
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
      tls = {
        secretName = "aerosol-tls"
        options    = "${var.namespace}/quickticket-alpn@kubernetescrd"
      } # valid *.aerosol.dev wildcard, Reflector-reflected into this ns
    }
  }
}

resource "kubernetes_manifest" "redis_dev_irtcp" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRouteTCP"
    metadata = {
      name      = "quickticket-redis-dev"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
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
      tls = {
        secretName = "aerosol-tls"
        # same option: harmless for redis (redis-py offers no ALPN)
        options = "${var.namespace}/quickticket-alpn@kubernetescrd"
      } # valid *.aerosol.dev wildcard, Reflector-reflected into this ns
    }
  }
}
