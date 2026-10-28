# Reflector — mirrors Secrets/ConfigMaps annotated with
# reflector.v1.k8s.emberstack.com/* into other namespaces. The wildcard
# *.vanderloch.com TLS secret depends on it, so this release keeps running as-is:
# every field below mirrors the live release, nothing here should produce a diff.
#
# Import (helm_release ID is namespace/name):
#   terraform import helm_release.reflector reflector/reflector
resource "helm_release" "reflector" {
  name       = "reflector"
  namespace  = "reflector"
  repository = "https://emberstack.github.io/helm-charts"
  chart      = "reflector"
  version    = "10.0.69"

  # Live release runs on chart defaults (helm get values -> null), so no values
  # are declared here on purpose.
  wait    = true
  timeout = 300

  # Deliberately NOT set (all default false outside the resource): atomic,
  # force_update, replace, reuse_values, reset_values, recreate_pods,
  # upgrade_install, create_namespace. Any of those could rewrite the live
  # release on an apply; a non-empty plan here means drift, not a to-do.
}

# Homepage — the homelab dashboard (gethomepage/homepage). Published as an OCI
# chart by the community maintainer; the live release came from that registry
# (chart `homepage` 4.2.0, appVersion v1.5.0). Everything below mirrors the live
# release; a non-empty plan here means drift, not a to-do.
#
# ns `homepage` is NOT managed by Terraform (no create_namespace) — see the
# follow-up note in the migration PR. The Traefik IngressRoute + TLS secret for
# the dashboard are also outside this release.
#
# Import (helm_release ID is namespace/name):
#   terraform import helm_release.homepage homepage/homepage
# then patch the `repository` attribute into state (import leaves it empty and
# helm provider v3 cannot ignore_changes it — see PR notes).
resource "helm_release" "homepage" {
  name       = "homepage"
  namespace  = "homepage"
  repository = "oci://ghcr.io/m0nsterrr/helm-charts"
  chart      = "homepage"
  version    = "4.2.0"

  # Live user values (`helm get values homepage -n homepage`). The release was
  # installed from a values file that mirrors the chart defaults except for
  # config.allowedHosts, so the whole set is reproduced key-for-key.
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

  # Deliberately NOT set: atomic, force_update, replace, reuse_values,
  # reset_values, recreate_pods, upgrade_install, create_namespace.
  #
  # MIGRATIONS.md row #15 (this import, PR #73) — comment-only change so the
  # docs update lands on a .tf-touching HEAD and Atlantis autoplans it.
}

# Pi-hole — CLUSTER DNS. Every DNS lookup in the homelab resolves through
# this release (my-pihole-dns-tcp / -udp on 192.168.10.166, DHCP on NodePort).
# Highest-risk app in the tier-4 batch: a bad apply here breaks name resolution
# for the whole cluster, so nothing below may diverge from the live release.
#
# Apply discipline (MIGRATIONS.md tier 4): apply must happen from INSIDE the
# cluster (Atlantis in-cluster, no desktop kubeconfig round trip) with an
# immediate DNS verification right after `atlantis apply` — e.g.
#   kubectl -n default run dns-verify --rm -i --restart=Never \
#     --image=busybox:1.36 --command -- nslookup pihole.vanderloch.com 192.168.10.166
# and a re-check that my-pihole-dns-{tcp,udp} still own 192.168.10.166.
#
# Import (helm_release ID is namespace/name):
#   terraform import helm_release.pihole default/my-pihole
# then patch `repository`, `chart`, `version` and `values` into state (import
# leaves them empty and helm provider v3 cannot ignore_changes them — same
# caveat as the homepage block above). Until the state patch lands, a plan
# reads as a full replace of the release, NOT as drift.
resource "helm_release" "pihole" {
  name       = "my-pihole"
  namespace  = "default"
  repository = "https://mojo2600.github.io/pihole-kubernetes/"
  chart      = "pihole"
  version    = "2.34.0"

  # Live user values (`helm get values my-pihole -n default`) — six leaf
  # overrides against the chart defaults plus two metallb annotations. Nothing
  # else is declared on purpose: everything else in `--all` output is chart
  # default (verified by diffing against `helm show values pihole --version
  # 2.34.0`), and pinning those would fake drift of its own.
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
    # my-pihole-custom-dnsmasq ConfigMap `addn-hosts` key. Verified against
    # chart 2.34.0 templates: 02-custom.conf (addn-hosts=/etc/addn-hosts +
    # dhcp-option=6) is chart DEFAULT and survives; only addn-hosts fills in.
    # The CM change flips checksum.config.dnsmasqConfig → pod rolls (~seconds
    # DNS blip, FTL cache flushes). Records previously lived ONLY in the
    # PVC's pihole.toml [dns] hosts array (hand-edited) — this makes them
    # declared + configurable; the toml array gets stripped after cutover
    # (see PR notes) so there is one source of truth.
    dnsmasq = {
      additionalHostsEntries = var.pihole_local_dns
    }
  })]

  wait    = true
  timeout = 300

  # Deliberately NOT set (all default false outside the resource): atomic,
  # force_update, replace, reuse_values, reset_values, recreate_pods,
  # upgrade_install, create_namespace. `atomic` on a DNS release would roll the
  # whole chart back mid-failure and take name resolution down with it.
  #
  # Also deliberately unmanaged: the `pihole` IngressRoute in ns default
  # (pihole.vanderloch.com, unmanaged sibling created a day after the install),
  # ns `default` itself, and the longhorn PVC the chart template owns.
}
