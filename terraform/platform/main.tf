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
  version    = "10.0.70"

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
  version    = "2.38.0"

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

# authentik — the IdP for the homelab (goauthentik.io). Chart `authentik` 2026.8.3
# (repo https://charts.goauthentik.io, chart tgz digest
# sha256:2e504b91da14b4f4f001681b392e0ac67870ab1453dec869247ad181272587be),
# installed 2026-09-20, revision 1, never upgraded. Everything below mirrors the
# live release; a non-empty plan here means drift, not a to-do.
#
# IF AUTHENTIK BREAKS, LOGINS BREAK (Traefik forwardAuth for auto-school and
# friends). Treat any non-no-op plan on this resource as a production incident:
# read the plan before applying, never apply blind.
#
# The chart bundles two dependencies (see Chart.yaml):
#   - postgresql 18.8.17 (oci://registry-1.docker.io/bitnamicharts, condition
#     postgresql.enabled) -> the `authentik-postgresql` StatefulSet + its 8Gi
#     Longhorn PVC `data-authentik-postgresql-0` are CHART-OWNED (labels
#     app.kubernetes.io/instance=authentik, helm.sh/chart=postgresql-18.8.17,
#     managed-by=Helm). Importing the release covers them; do NOT author the STS
#     as a separate typed resource.
#   - authentik-remote-cluster 2.1.0 aliased `serviceAccount` (condition
#     serviceAccount.create) -> SA/Role/RoleBinding/ClusterRole/ClusterRoleBinding
#     `authentik*`, also chart-owned.
#
# NOT part of this release (unmanaged, deliberately out of scope here):
#   - ns `authentik` itself (no create_namespace; see terraform/apps/namespaces.tf
#     follow-up — the ns is not TF-managed anywhere yet).
#   - IngressRoute `authentik` (auth.vanderloch.com, entryPoints outbound+websecure,
#     class traefik-external) — hand-applied, outside the chart.
#   - ServiceAccount/Role/RoleBinding `authentik` in ns authentik is chart-owned,
#     but svc+ingress `ak-outpost-authentik-embedded-outpost` are created at
#     runtime by authentik's embedded outpost controller
#     (app.kubernetes.io/managed-by=goauthentik.io) — never import those.
#   - secret `lochis-tls` (Reflector copy).
#
# Import (helm_release ID is namespace/name):
#   terraform import helm_release.authentik authentik/authentik
# then patch the `repository` attribute into state (import leaves it empty and
# helm provider v3 cannot ignore_changes it — same caveat as `helm_release.homepage`).
#
# PRE-MERGE PREREQUISITES (the values below are real secrets, this repo is PUBLIC):
#   1. add 4 keys to Secret `atlantis-app-vars` (ns ops):
#        AUTHENTIK_SECRET_KEY, AUTHENTIK_BOOTSTRAP_PASSWORD,
#        AUTHENTIK_POSTGRESQL_PASSWORD, AUTHENTIK_REDIS_PASSWORD
#      (values = current live ones; see notes.md for how to read them back, never
#       commit them).
#   2. add the matching TF_VAR_authentik_* entries to helm/atlantis/values.yaml
#      `environmentSecrets`, helm upgrade atlantis, restart atlantis-0.
#   3. only then open/refresh this PR — otherwise the plan fails fast with
#      "No value for required variable".
resource "helm_release" "authentik" {
  name       = "authentik"
  namespace  = "authentik"
  repository = "https://charts.goauthentik.io"
  chart      = "authentik"
  version    = "2026.8.5"

  # Live user values, reproduced key-for-key (`helm get values authentik -n
  # authentik`). The four credentials are injected from sensitive root vars
  # (Secret atlantis-app-vars -> TF_VAR_authentik_*) instead of literals because
  # this repo is public; the rendered values are byte-identical to the live
  # release. Note `authentik.postgresql.password` and `postgresql.auth.password`
  # are the SAME live string and must stay in lockstep (server-side DB auth vs.
  # the bitnami subchart's secret) — that is why one variable feeds both.
  #
  # `redis.*` is inert in chart 2026.8.3 (no redis subchart, no redis workload,
  # no AUTHENTIK_REDIS__* key in the rendered Secret), but the keys are in the
  # live release's values and are reproduced here so the import plans clean.
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

  # Deliberately NOT set (all default false outside the resource): atomic,
  # force_update, replace, reuse_values, reset_values, recreate_pods,
  # upgrade_install, create_namespace, dependency_update, max_history, lint,
  # verify, disable_webhook, disable_openapi_validation, cleanup_on_fail,
  # set/set_sensitive/set_list blocks. Any of those could rewrite the live IdP
  # release on an apply.
  #
  # CAUTION: helm provider calls `helm upgrade` on ANY attribute change, so even
  # touching `timeout` (e.g. raising it to 1800 for a real upgrade) re-runs an
  # upgrade against the live release. Budget for that deliberately.
}
# cert-manager — the cluster's entire TLS trust path. It issues/renews every
# certificate backing the Traefik routes (wildcard *.vanderloch.com included),
# so this release keeps running exactly as-is: every field below mirrors the
# LIVE release (chart cert-manager v1.19.1, Helm revision 24, deployed
# 2025-11-05T16:58:27Z) so a post-merge import yields a no-op plan.
#
# IMPORTANT: import must pin the EXACT chart version currently live (v1.19.1).
# The release is at revision 24 after many upgrades; importing "latest" would
# rewrite the live release on the next apply.
#
# Import (helm_release ID is namespace/name):
#   terraform import helm_release.cert_manager cert-manager/cert-manager
# then check state's `repository`: helm provider import can leave it empty
# (same quirk as the homepage import) — patch it to
# https://charts.jetstack.io if the plan shows a repository-only diff.
#
# NOT managed here: the 6 cert-manager CRDs (chart has installCRDs=false and
# crds.enabled=false, so they are cluster-installed and unowned-by-Helm), the
# ClusterIssuer `letsencrypt-production`, and the ns (pre-exists, Rancher-owned).
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

  # Deliberately NOT set (all default false outside the resource): atomic,
  # force_update, replace, reuse_values, reset_values, recreate_pods,
  # upgrade_install, create_namespace, dependency_update, max_history,
  # cleanup_on_fail. Any of those could rewrite the live release on an apply;
  # a non-empty plan here means drift, not a to-do.
}

# Traefik — the cluster's only ingress controller (Traefik v3.5.3, chart
# traefik-37.2.0 from the official repo https://helm.traefik.io/traefik).
#
# !!! MERGE + IMPORT THIS LAST IN TIER 4 !!!
# Order is: reflector -> homepage -> pihole -> cert-manager -> authentik ->
# traefik. Every route in the cluster rides this release, including Atlantis's
# own webhook path (https://atlantis.vanderloch.com:2459). An apply that
# restarts traefik (even a harmless values no-op that forces a rollout) briefly
# interrupts ALL ingress, which also strands the webhook that would report the
# result. Plan the apply for a quiet window, with no plans in flight.
#
# The release is ONLY the chart: deployment (2 replicas), LB Service
# `traefik` (web 80 / websecure 443 / outbound 2459 / outbound2 2460),
# ServiceAccount/RBAC, IngressClass `traefik`. It does NOT own:
#   - IngressRoutes / Middlewares / TLSOptions — managed as CRDs in
#     terraform/apps (apps), plus a few hand-made ones in ns traefik (see
#     notes.md, "unmanaged siblings").
#   - Service `traefik-outbound` (192.168.10.17) — hand-rolled, not in the
#     release manifest. Leave it alone.
#   - CRDs: chart ships crds/ (24 files) which helm applies on *install* only;
#     they already exist in the cluster (installed 2025-10-30).
#
# Import (helm_release ID is namespace/name):
#   terraform import helm_release.traefik traefik/traefik
# The first post-import plan MUST be a no-op. Non-empty plan = drift, stop.
resource "helm_release" "traefik" {
  name       = "traefik"
  namespace  = "traefik"
  repository = "https://helm.traefik.io/traefik"
  chart      = "traefik"
  version    = "42.1.3"

  # Live user values, verbatim from `helm get values traefik -n traefik`
  # (revision 10, deployed 2026-09-02). Reproduced key-for-key — every entry
  # here is load-bearing for the cluster's routing:
  #   - providers.kubernetesCRD.ingressClass = traefik-external is why Traefik
  #     only watches IngressRoutes annotated kubernetes.io/ingress.class:
  #     traefik-external. Changing it silently drops every app route.
  #   - ports.web redirection is the 80 -> 443 permanent redirect.
  #   - ports.outbound/outbound2 (2459/2460, TLS) carry the external DNAT
  #     routes (e.g. https://abs.vanderloch.com:2459).
  #   - ingressRoute.dashboard.enabled = false: the traefik.vanderloch.com
  #     dashboard IngressRoute + basic-auth middleware in the ns are hand-made
  #     and unmanaged (see notes.md).
  values = [yamlencode({
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

  # Deliberately NOT set (all default false outside the resource): atomic,
  # force_update, replace, reuse_values, reset_values, recreate_pods,
  # upgrade_install, create_namespace, dependency_update, max_history, lint,
  # verify, disable_webhook, disable_openapi_validation, cleanup_on_fail,
  # set/set_sensitive/set_list blocks. Any of those could rewrite the live IdP
  # release on an apply.
  #
  # CAUTION: helm provider calls `helm upgrade` on ANY attribute change, so even
  # touching `timeout` (e.g. raising it to 1800 for a real upgrade) re-runs an
  # upgrade against the live release. Budget for that deliberately.
  # upgrade_install, create_namespace. `atomic` in particular would roll back a
  # failed upgrade of the ingress controller — do not enable it here; a failed
  # apply must be inspected, not auto-reverted.
  # `create_namespace` stays unset: ns `traefik` pre-exists and is not managed
  # by Terraform.
}

# metallb — the ONLY working LB IPAM (kube-vip is CP-VIP-only, svc_enable=false).
# Adopted 2026-10-29 from hand-applied raw v0.13.12 manifests via delete-and-
# reinstall cutover (immutable selectors made --take-ownership impossible —
# full story in MIGRATIONS.md #21 + plans/ off-repo). Bumped 0.13.12 → 0.16.1
# same day AFTER pre-applying the 0.16 CRDs by hand: kubectl apply --server-side
# --force-conflicts --field-manager=helm of the rendered crds subchart +
# helm.sh/resource-policy=keep on every CRD (helm must never delete them —
# dropping ipaddresspools releases every VIP). CRDs stay OUT of the release
# (crds.enabled=false): the 0.13 chart's conversion-webhook caBundle SSA-
# conflicted with the controller's rotated cert; at 0.16 conversion webhooks
# are GONE from the CRDs, so a future hygiene PR can flip crds.enabled=true —
# until then renovate bumps for metallb are disabled (see renovate.json5)
# because a plain bump without the CRD ceremony crashloops the workloads
# (missing ServiceBGPStatus/ServiceL2Status kinds, incident PR #115).
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

  # Deliberately NOT set: atomic, force_update, replace, recreate_pods,
  # upgrade_install, create_namespace, etc. (same discipline as traefik above —
  # never auto-rollback or surprise-roll the LB data plane).
  #
  # Unmanaged by this release (do not author them here):
  #   - ns `metallb-system` itself (pod-security labels = privileged, preserved)
  #   - IPAddressPool `first-pool` (192.168.10.160-200 + 192.168.10.17/32) and
  #     L2Advertisement `example` — pre-date the release, hand-applied; typed
  #     kubernetes_manifest follow-up per MIGRATIONS.md #21
  #   - the 8 metallb.io CRDs (helm crds/ dir, apply-only — the 0.13.12 set is
  #     identical live; a chart bump must kubectl-apply new CRDs manually)
  #   - the 12 LB Services consuming the pools (pihole's shared-IP .166
  #     annotation lives in the pihole release's values, not here)
}

# metallb pool CRs — hand-applied at the original 2025 install, typed since
# 2026-10-29 (MIGRATIONS.md #21 follow-up) so the VIP allocation policy is
# reviewable in git: .160-.200 general range + the single /32 for
# traefik-outbound (.17, source-IP-stable egress). IMPORTED, not created —
# and until the import lands, any terraform-platform apply from a branch
# without these blocks plans their DESTRUCTION (= VIP release).
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

# longhorn backup target — Garage S3 (bucket "longhorn") served from a pve1 LXC.
# Longhorn 1.9 configures targets via the BackupTarget CR (the old settings
# backup-target / backup-target-credential-secret are gone); "default" existed
# empty since install and was IMPORTED, not created. Credentials live in the
# Secret below, values via TF_VARs from atlantis-app-vars (LONGHORN_BACKUP_*);
# the endpoint URL is an infra detail and never appears in this repo.
# Precondition for MIGRATIONS.md #24 adoption: one restore must be proven
# through this target before any RecurringJob is added.
resource "kubernetes_manifest" "longhorn_backuptarget" {
  field_manager {
    force_conflicts = true # longhorn-manager owns the seeded empty defaults
  }
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "BackupTarget"
    metadata = {
      name      = "default"
      namespace = "longhorn-system"
    }
    spec = {
      backupTargetURL  = "s3://longhorn@garage/"
      credentialSecret = kubernetes_secret.longhorn_backup.metadata[0].name
    }
  }
}

resource "kubernetes_secret" "longhorn_backup" {
  metadata {
    name      = "longhorn-backup"
    namespace = "longhorn-system"
  }

  data = {
    AWS_ACCESS_KEY_ID     = var.longhorn_backup_access_key
    AWS_SECRET_ACCESS_KEY = var.longhorn_backup_secret_key
    AWS_ENDPOINTS         = var.longhorn_backup_endpoint
  }
}

# longhorn daily backup — the ONLY working backup path in 1.9.2: user-created
# Backup CRs die in the admission webhook (no-route bug), manager/recurring-
# job-created backups are fine (proven: full-cluster kickoff + restore proof,
# 2026-10-29, see MIGRATIONS.md #24). Group "default" is stamped on every
# volume by the longhorn mutator, so this covers all attached volumes;
# detached orphans are skipped by design. Cron is UTC — 07:00Z = 02:00
# America/Toronto in winter (EST), 03:00 during DST.
resource "kubernetes_manifest" "longhorn_recurringjob_daily_backup" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"
    metadata = {
      name      = "daily-backup"
      namespace = "longhorn-system"
    }
    spec = {
      name        = "daily-backup" # must match metadata.name
      cron        = "0 7 * * *"
      task        = "backup"
      retain      = 14
      concurrency = 1
      groups      = ["default"]
    }
  }
}

