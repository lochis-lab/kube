# Reflector target list for the wildcard cert (traefik ns, source of
# lochis-tls copies). These annotations were previously maintained by hand
# with `kubectl annotate` — the list below is the drift-free, in-git version
# going forward (annotations on the SECRET: cert-manager preserves them
# across renewals; kubernetes_annotations patches metadata only, it does not
# own or replace the Secret).
#
# 2026-11: pelican added as a latent-gap fix — its IngressRoute has
# referenced lochis-tls since the pterodactyl cutover, but the ns never had a
# copy (it was missing from the hand-maintained list) and no TLSStore default
# exists, so that route was serving Traefik's default cert.
# opengym added with its module (this PR).
resource "kubernetes_annotations" "lochis_tls_reflector" {
  api_version = "v1"
  kind        = "Secret"
  metadata {
    name      = "lochis-tls"
    namespace = "traefik"
  }
  annotations = {
    "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true"
    "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = join(",", [
      "paloch", "homepage", "vocard", "pterodactyl", "cloudreve",
      "audiobookshelf", "headscale", "osu-tracker", "homeassistant",
      "firecrawl", "auto-school", "pi-omni", "micro-transcribe",
      "authentik", "ops", "pelican", "opengym",
    ])
    "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true"
    "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = "^(paloch|homepage|vocard|pterodactyl|cloudreve|audiobookshelf|headscale|osu-tracker|homeassistant|firecrawl|auto-school|pi-omni|micro-transcribe|authentik|ops|pelican|opengym)$"
  }
}
