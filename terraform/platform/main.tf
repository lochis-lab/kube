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
  version    = "10.0.65"

  # Live release runs on chart defaults (helm get values -> null), so no values
  # are declared here on purpose.
  wait    = true
  timeout = 300

  # Deliberately NOT set (all default false outside the resource): atomic,
  # force_update, replace, reuse_values, reset_values, recreate_pods,
  # upgrade_install, create_namespace. Any of those could rewrite the live
  # release on an apply; a non-empty plan here means drift, not a to-do.
}
