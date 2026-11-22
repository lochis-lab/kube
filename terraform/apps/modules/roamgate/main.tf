# Roamgate — herdr web/PWA client. Runs OUTSIDE the cluster on the
# happy-agent-01 VM (LAN 192.168.10.146, tailnet 100.64.0.87); this module
# only publishes it: selector-less Service + Endpoints → IngressRoute on
# websecure :443. TAILNET/LAN-ONLY by design: no Cloudflare tunnel entry, so
# the hostname never leaves the homelab.
#
# Why Endpoints and not ExternalName: cluster CoreDNS forwards to the nodes'
# resolv.conf, which is NOT Pi-hole — pods resolve public DNS only, so a
# split-DNS upstream name is unreachable from Traefik (lesson: 2026-11-22,
# roamgate 502). A static Endpoints IP needs no DNS at all. The IP is a
# Pi-hole DHCP address — keep the lease reserved on the VM's MAC.

variable "namespace" {
  type = string
}

variable "roamgate_vm_ip" {
  description = "LAN IP of the happy-agent-01 VM (Pi-hole DHCP-reserved)"
  type        = string
  default     = "192.168.10.146"
}

variable "roamgate_port" {
  type    = number
  default = 8787
}

resource "kubernetes_service_v1" "roamgate" {
  metadata {
    name      = "roamgate"
    namespace = var.namespace
  }
  spec {
    port {
      port        = var.roamgate_port
      target_port = var.roamgate_port
    }
    # selector-less: endpoints are managed manually below
  }
}

resource "kubernetes_endpoints_v1" "roamgate" {
  metadata {
    name      = kubernetes_service_v1.roamgate.metadata[0].name
    namespace = var.namespace
  }
  subset {
    address {
      ip = var.roamgate_vm_ip
    }
    port {
      port = var.roamgate_port
    }
  }
}
