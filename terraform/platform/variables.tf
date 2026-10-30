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

# Companion addition for terraform/platform/variables.tf — REQUIRED for the
# authentik helm_release block (values reference these). Same pattern as
# terraform/apps/variables.tf: values arrive as TF_VAR_authentik_* injected by the
# Atlantis chart `environmentSecrets` from Secret `atlantis-app-vars` (ns ops),
# so they are never committed. Plans redact them natively (the whole `values`
# attribute of the helm_release is tainted sensitive by interpolation).
#
# Desktop plan:
#   for k in SECRET_KEY BOOTSTRAP_PASSWORD POSTGRESQL_PASSWORD REDIS_PASSWORD; do
#     export TF_VAR_authentik_$(echo $k | tr 'A-Z' 'a-z')=$(
#       kubectl -n ops get secret atlantis-app-vars -o jsonpath="{.data.AUTHENTIK_$k}" | base64 -d)
#   done
#   export TF_VAR_kubeconfig_path=$HOME/.kube/config

variable "authentik_secret_key" {
  description = "authentik AUTHENTIK_SECRET_KEY (chart values authentik.secret_key)"
  type        = string
  sensitive   = true
}

variable "authentik_bootstrap_password" {
  description = "authentik bootstrap admin password (chart values authentik.password -> AUTHENTIK_PASSWORD)"
  type        = string
  sensitive   = true
}

variable "authentik_postgresql_password" {
  description = "authentik DB password; feeds BOTH authentik.postgresql.password and postgresql.auth.password (must match live)"
  type        = string
  sensitive   = true
}

variable "authentik_redis_password" {
  description = "Legacy redis.auth.password carried in the live release values; inert in chart 2026.8.3 but kept for a clean import"
  type        = string
  sensitive   = true
}

