# Reflector — mirrors Secrets/ConfigMaps annotated with
# reflector.v1.k8s.emberstack.com/* into other namespaces. The wildcard
# *.vanderloch.com TLS secret depends on it, so this release keeps running as-is:
resource "helm_release" "reflector" {
  name       = "reflector"
  namespace  = "reflector"
  repository = "https://emberstack.github.io/helm-charts"
  chart      = "reflector"
  version    = "10.0.70"
  wait    = true
  timeout = 300

}

# Homepage — the homelab dashboard (gethomepage/homepage). Published as an OCI
resource "helm_release" "homepage" {
  name       = "homepage"
  namespace  = "homepage"
  repository = "oci://ghcr.io/m0nsterrr/helm-charts"
  chart      = "homepage"
  version    = "4.2.0"

  values = [yamlencode({
    config = {
      allowedHosts = ["homepage.vanderloch.com"]
    }
    extraEnv         = []
    extraEnvFrom     = []
    fullnameOverride = ""
    image = {
      pullPolicy = "IfNotPresent"
      registry   = "ghcr.io"
      repository = "gethomepage/homepage"
      sha        = ""
      tag        = ""
    }
    imagePullSecrets = []
    ingress = {
      annotations = {}
      enabled     = false
      hosts = [{
        host = "chart-example.local"
        paths = [{
          path     = "/"
          pathType = "ImplementationSpecific"
        }]
      }]
      ingressClassName = ""
      tls              = []
    }
    nameOverride   = ""
    nodeSelector   = {}
    podAnnotations = {}
    podLabels      = {}
    podSecurityContext = {
      fsGroup             = 1000
      fsGroupChangePolicy = "OnRootMismatch"
    }
    rbac = {
      enabled = true
    }
    replicaCount = 1
    resources    = {}
    securityContext = {
      allowPrivilegeEscalation = false
      capabilities = {
        drop = ["ALL"]
      }
      privileged             = false
      readOnlyRootFilesystem = false
      runAsGroup             = 1000
      runAsNonRoot           = true
      runAsUser              = 1000
      seccompProfile = {
        type = "RuntimeDefault"
      }
    }
    service = {
      port = 80
      type = "ClusterIP"
    }
    serviceAccount = {
      annotations = {}
      automount   = true
      create      = true
      name        = ""
    }
    tolerations  = []
    volumeMounts = []
    volumes      = []
  })]

  wait    = true
  timeout = 300

}

# Pi-hole — CLUSTER DNS. Every DNS lookup in the homelab resolves through
# this release (my-pihole-dns-tcp / -udp on 192.168.10.166, DHCP on NodePort).
# Highest-risk app in the tier-4 batch: a bad apply here breaks name resolution
# for the whole cluster, so nothing below may diverge from the live release.
#
resource "helm_release" "pihole" {
  name       = "my-pihole"
  namespace  = "default"
  repository = "https://mojo2600.github.io/pihole-kubernetes/"
  chart      = "pihole"
  version    = "2.38.0"

  values = [yamlencode({
    persistentVolumeClaim = {
      enabled = true
    }
    serviceDns = {
      annotations = {
        "metallb.universe.tf/allow-shared-ip" = "pihole-svc"
      }
      loadBalancerIP = "192.168.10.166"
      type           = "LoadBalancer"
    }
    serviceWeb = {
      annotations = {
        "metallb.universe.tf/allow-shared-ip" = "pihole-svc"
      }
      loadBalancerIP = "192.168.10.175"
      type           = "LoadBalancer"
    }
    # Local split-DNS records → chart renders them into the
    # my-pihole-custom-dnsmasq ConfigMap `addn-hosts` 
    dnsmasq = {
      additionalHostsEntries = var.pihole_local_dns
    }
  })]

  wait    = true
  timeout = 300

}

resource "helm_release" "authentik" {
  name       = "authentik"
  namespace  = "authentik"
  repository = "https://charts.goauthentik.io"
  chart      = "authentik"
  version    = "2026.8.5"

  values = [yamlencode({
    authentik = {
      error_reporting = {
        enabled = false
      }
      password = var.authentik_bootstrap_password
      postgresql = {
        password = var.authentik_postgresql_password
      }
      secret_key = var.authentik_secret_key
    }
    postgresql = {
      auth = {
        password = var.authentik_postgresql_password
      }
      enabled = true
      primary = {
        persistence = {
          enabled = true
          size    = "8Gi"
        }
      }
    }
    redis = {
      auth = {
        password = var.authentik_redis_password
      }
      enabled = true
    }
    server = {
      ingress = {
        enabled = false
      }
      resources = {
        requests = {
          cpu    = "300m"
          memory = "768Mi"
        }
      }
    }
    worker = {
      resources = {
        requests = {
          cpu    = "200m"
          memory = "512Mi"
        }
      }
    }
  })]

  wait    = true
  timeout = 300

}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.21.3"

  # Live user values verbatim (`helm get values cert-manager -n cert-manager`),
  # reproduced key-for-key. Do not "tidy" this: the podDnsPolicy=None +
  # podDnsConfig.nameservers pair and the two DNS01 extraArgs are what let
  # ACME HTTP01/DNS01 validation work from this network, and replicaCount=3 is
  # the live controller HA setting.
  values = [yamlencode({
    extraArgs = [
      "--dns01-recursive-nameservers=1.1.1.1:53,9.9.9.9:53",
      "--dns01-recursive-nameservers-only",
    ]
    installCRDs = false
    podDnsConfig = {
      nameservers = ["1.1.1.1", "9.9.9.9"]
    }
    podDnsPolicy = "None"
    replicaCount = 3
  })]

  # Mirrors the reflector release: the chart ships a startupapicheck Job, so we
  # wait for readiness the same way the live install did.
  wait    = true
  timeout = 300

}

resource "helm_release" "traefik" {
  name       = "traefik"
  namespace  = "traefik"
  repository = "https://helm.traefik.io/traefik"
  chart      = "traefik"
  version    = "42.2.0"

  values = [yamlencode({
       service = {
      spec = {
        loadBalancerIP = "192.168.10.170"
      }
    }
    additionalArguments = [
      "--serversTransport.insecureSkipVerify=true",
      "--log.level=INFO",
      # moved from globalArguments (chart 38.1.0 removed that root key):
      # telemetry opt-outs, functionally identical as static args
      "--global.sendanonymoususage=false",
      "--global.checknewversion=false",
    ]
    deployment = {
      replicas = 2
    }
    ingressRoute = {
      dashboard = {
        enabled = false
      }
    }
    nodeSelector = {
      worker = "true"
    }
    ports = {
      outbound = {
        expose = {
          default = true
        }
        exposedPort = 2459
        port        = 2459
        protocol    = "TCP"
        # chart 38.1+: per-port `tls` moved under `http.tls`
        http = {
          tls = {
            enabled = true
          }
        }
      }
      outbound2 = {
        expose = {
          default = true
        }
        exposedPort = 2460
        port        = 2460
        protocol    = "TCP"
        http = {
          tls = {
            enabled = true
          }
        }
      }
      web = {
        # chart 38.1+: `redirections` moved under `http.redirections`
        http = {
          redirections = {
            entryPoint = {
              permanent = true
              scheme    = "https"
              to        = "websecure"
            }
          }
        }
      }
      websecure = {
        http = {
          tls = {
            enabled = true
          }
        }
      }
    }
    providers = {
      kubernetesCRD = {
        allowExternalNameServices = true
        enabled                   = true
        ingressClass              = "traefik-external"
      }
      kubernetesIngress = {
        allowExternalNameServices = true
        enabled                   = true
        publishedService = {
          enabled = false
        }
      }
    }
    rbac = {
      enabled = true
    }
    service = {
      enabled = true
      type    = "LoadBalancer"
    }
  })]

  wait    = true
  timeout = 300

}

resource "helm_release" "metallb" {
  name       = "metallb"
  namespace  = "metallb-system"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = "0.16.1" # app v0.16.1 — bumped from 0.13.12 on 2026-10-29 (CRD ceremony below)

  # Only live non-defaults: pod scrape annotations (prometheus.io/port=7472
  # metrics endpoints) and frrk8s.enabled=false (0.16 defaults the frr-k8s BGP
  # subchart ON; this cluster is L2-only). crds.enabled defaults TRUE since the
  # 0.16.1 flip — 0.16 CRDs have no conversion webhooks, so the 0.13 caBundle
  # SSA-conflict class is gone and the subchart applies cleanly; every CRD also
  # still carries helm.sh/resource-policy=keep as a belt-and-braces guard.
  values = [yamlencode({
    frrk8s = {
      enabled = false
    }
    prometheus = {
      scrapeAnnotations = true
    }
  })]

  wait    = true
  timeout = 300

}

resource "kubernetes_manifest" "metallb_first_pool" {
  field_manager {
    # the CRs were originally kubectl client-side applied — take the fields
    force_conflicts = true
  }
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "first-pool"
      namespace = "metallb-system"
    }
    spec = {
      addresses = [
        "192.168.10.160-192.168.10.200",
        "192.168.10.17/32",
      ]
      autoAssign    = true
      avoidBuggyIPs = false
    }
  }
}

resource "kubernetes_manifest" "metallb_l2advertisement" {
  field_manager {
    force_conflicts = true
  }
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "example"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = ["first-pool"]
    }
  }
}

# longhorn resources (BackupTarget/backup secret/RecurringJob + the adopted
# helm release) moved 2026-10-30 to terraform/longhorn — pilot of the per-app
# root-module layout; see that dir and MIGRATIONS.md.

