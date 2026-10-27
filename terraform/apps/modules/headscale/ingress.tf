# TAILNET CONTROL PLANE ROUTING — the four routes that keep 100.64.0.0/10 alive.
#
# headscale (web) + headscale-tcp (gRPC) ride the `outbound` entrypoint :2459
# (the DNAT'd public port). headscale-tcp is TLS PASSTHROUGH on purpose — no
# tls.secretName; SNI-sniffed straight to the pod's gRPC listener :50443.
# TLS termination there chokes (see quickticket ALPN lesson), don't "fix" it.
#
# console + metrics ride the standard websecure :443.

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
      routes = [{
        kind  = "Rule"
        match = "Host(`headscale.vanderloch.com`) && PathPrefix(`/metrics`)"
        services = [{
          name = "headscale"
          port = 9090
        }]
      }]
      tls = { secretName = "lochis-tls" }
    }
  }
}
