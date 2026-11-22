# Roamgate — herdr web/PWA client. Runs OUTSIDE the cluster on the
# happy-agent-01 VM (100.64.0.87, tailnet); this module only publishes it:
# ExternalName service → IngressRoute on websecure :443. TAILNET-ONLY by
# design: no Cloudflare tunnel entry, so the hostname never leaves the
# homelab (the VM record lives in platform's pihole_local_dns).

variable "namespace" {
  type = string
}

variable "roamgate_upstream" {
  description = "Split-DNS name of the VM running roamgate (see platform pihole_local_dns)"
  type        = string
  default     = "happy-agent-01.vanderloch.com"
}

resource "kubernetes_service_v1" "roamgate" {
  metadata {
    name      = "roamgate"
    namespace = var.namespace
  }
  spec {
    type         = "ExternalName"
    externalName = var.roamgate_upstream
  }
}
