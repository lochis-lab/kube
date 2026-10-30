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
        # this cluster's traefik CRD types `options` as an object, not the
        # "ns/name@kubernetescrd" string form
        options = {
          name      = "quickticket-alpn"
          namespace = var.namespace
        }
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
        options = {
          name      = "quickticket-alpn"
          namespace = var.namespace
        }
      } # valid *.aerosol.dev wildcard, Reflector-reflected into this ns
    }
  }
}

# ---- HTTP app routes (added 2026-11) ---------------------------------------
# One host per env; the SPA (web) serves /, the API is path-split under /api.
# The frontend builds with no VITE_API_URL (same-origin ""), so no CORS is
# involved. Same cert/entrypoint/class as the TCP routes above.

resource "kubernetes_manifest" "qt_dev_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "quickticket-dev"
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
          match = "Host(`qt-dev.aerosol.dev`) && PathPrefix(`/api`)"
          services = [{ name = "quickticket-dev", port = 8000, scheme = "http" }]
        },
        {
          kind     = "Rule"
          match    = "Host(`qt-dev.aerosol.dev`)"
          priority = 1 # lower precedence than the /api rule
          services = [{ name = "quickticket-dev-web", port = 80, scheme = "http" }]
        }
      ]
      tls = { secretName = "aerosol-tls" } # *.aerosol.dev wildcard, Reflector
    }
  }
}

resource "kubernetes_manifest" "qt_prod_ir" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "quickticket-prod"
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
          match = "Host(`quickticket.aerosol.dev`) && PathPrefix(`/api`)"
          services = [{ name = "quickticket-prod", port = 8000, scheme = "http" }]
        },
        {
          kind     = "Rule"
          match    = "Host(`quickticket.aerosol.dev`)"
          priority = 1
          services = [{ name = "quickticket-prod-web", port = 80, scheme = "http" }]
        }
      ]
      tls = { secretName = "aerosol-tls" }
    }
  }
}
