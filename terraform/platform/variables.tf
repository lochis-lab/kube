# Empty default = in-cluster provider config (Atlantis).
# Desktop: export TF_VAR_kubeconfig_path=$HOME/.kube/config
variable "kubeconfig_path" {
  description = "Path to kubeconfig for local runs; empty means in-cluster"
  type        = string
  default     = ""
}

# Pihole local split-DNS host records (dnsmasq.additionalHostsEntries), in
# "IP hostname" form. Deliberately plain literals in git (decision over the
# TF_VAR/Secret alternative): the repo already publishes the pihole LB VIPs,
# RFC1918 topology is not sensitive, and records in git = reviewable diffs,
# history, and single source of truth. TF_VAR_pihole_local_dns can still
# override locally for experiments.
variable "pihole_local_dns" {
  description = "Pihole local DNS host records rendered into the chart's addn-hosts ConfigMap key"
  type        = list(string)
  default = [
    "192.168.10.170 pihole.vanderloch.com",
    "192.168.10.170 pelican.vanderloch.com",
    "192.168.10.170 traefik.vanderloch.com",
    "192.168.10.170 homepage.vanderloch.com",
    "192.168.10.170 jackett.vanderloch.com",
    "192.168.10.170 wyze.vanderloch.com",
    "192.168.10.170 pterodactyl.vanderloch.com",
    "192.168.10.170 headscaleconsole.vanderloch.com",
    "192.168.10.170 kubero.vanderloch.com",
    "192.168.10.170 registry.vanderloch.com",
    "192.168.10.170 registry.kubero.vanderloch.com",
    "192.168.10.170 n8n.vanderloch.com",
    "192.168.10.170 omniroute.vanderloch.com",
    "192.168.10.170 ha.vanderloch.com",
    "192.168.10.170 firecrawl.vanderloch.com",
    "192.168.10.170 headscale.vanderloch.com",
  ]
}
