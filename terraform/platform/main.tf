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
