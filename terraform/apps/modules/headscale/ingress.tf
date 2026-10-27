# TAILNET CONTROL PLANE ROUTING — the four routes that keep 100.64.0.0/10 alive.
#
# headscale (web) + headscale-tcp (gRPC) ride the `outbound` entrypoint :2459
# (the DNAT'd public port). headscale-tcp is TLS PASSTHROUGH on purpose — no
# tls.secretName; SNI-sniffed straight to the pod's gRPC listener :50443.
# TLS termination there chokes (see quickticket ALPN lesson), don't "fix" it.
#
# console + metrics ride the standard websecure :443.

# CORS: console is served cross-origin (internal websecure host) while the
# browser client WSS's to the control plane on :2459. WebSockets need no CORS,
# but any fetch from the console page does — allow exactly the console origin
# on headscale's outbound responses (upstream-supported option B from deploy.md).
resource "kubernetes_manifest" "console_cors" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "headscale-console-cors"
      namespace = var.namespace
    }
    spec = {
      headers = {
        accessControlAllowOriginList  = ["https://headscaleconsole.vanderloch.com"]
        accessControlAllowHeaders     = ["Authorization", "Content-Type"]
        accessControlAllowMethods     = ["GET", "POST", "OPTIONS"]
        addVaryHeader                 = true
      }
    }
  }
}

resource "kubernetes_manifest" "headscale_ir" {
  field_manager {
    force_conflicts = true # kubectl-client-side-apply also claims these fields
  }
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "headscale"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["outbound"]
      routes = [{
        kind  = "Rule"
        match = "Host(`headscale.vanderloch.com`)"
        middlewares = [{
          name = "headscale-console-cors"
        }]
        services = [{
          name = "headscale"
          port = 8080
        }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}

# gRPC / coordination — HostSNI passthrough on :2459. THE critical route:
# tailscaled clients on the tailnet talk through this every few seconds.
resource "kubernetes_manifest" "headscale_tcp" {
  field_manager {
    force_conflicts = true # portainer SSA owns its io.portainer.* labels here — we take the object over
  }
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRouteTCP"
    metadata = {
      name      = "headscale-tcp"
      namespace = var.namespace
      # portainer-era io.portainer.* labels deliberately dropped (portainer is
      # slated for decommission; label removal is an inert in-place update)
    }
    spec = {
      entryPoints = ["outbound"]
      routes = [{
        match = "HostSNI(`headscale.vanderloch.com`)"
        services = [{
          name = "headscale"
          port = 50443
        }]
      }]
    }
  }
}

resource "kubernetes_manifest" "console_ir" {
  field_manager {
    force_conflicts = true
  }
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "headscale-console"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind  = "Rule"
        match = "Host(`headscaleconsole.vanderloch.com`) && PathPrefix(`/admin`)"
        services = [{
          name = "headscale"
          port = 3000
        }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}

# websecure :443 — REQUIRED for the browser console: its WS dialer strips the
# port and connects to the control host on 443 only (upstream deploy.md).
# Host-only rule catches /ts2021 + everything else; the longer /metrics rule
# below still wins for metrics → 9090.
resource "kubernetes_manifest" "metrics_ir" {
  field_manager {
    force_conflicts = true
  }
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "headscale-metrics"
      namespace = var.namespace
      annotations = {
        "kubernetes.io/ingress.class" = "traefik-external"
      }
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          kind  = "Rule"
          match = "Host(`headscale.vanderloch.com`) && PathPrefix(`/metrics`)"
          services = [{
            name = "headscale"
            port = 9090
          }]
        },
        {
          kind  = "Rule"
          match = "Host(`headscale.vanderloch.com`)"
          middlewares = [{
            name = "headscale-console-cors"
          }]
          services = [{
            name = "headscale"
            port = 8080
          }]
        },
      ]
      tls = { secretName = "lochis-tls" }
    }
  }
}
