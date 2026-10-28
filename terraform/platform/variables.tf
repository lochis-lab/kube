# Empty default = in-cluster provider config (Atlantis).
# Desktop: export TF_VAR_kubeconfig_path=$HOME/.kube/config
variable "kubeconfig_path" {
  description = "Path to kubeconfig for local runs; empty means in-cluster"
  type        = string
  default     = ""
}

# Pihole local split-DNS host records (dnsmasq.additionalHostsEntries), in
# "IP hostname" form. Required + sensitive on purpose (public repo):
#  - no default → plans fail fast with "No value for required variable" until
#    the TF_VAR is wired (atlantis-app-vars Secret → Atlantis environmentSecrets,
#    same pattern as the authentik credentials), instead of silently planning
#    to strip the records (which would break split-DNS for the whole LAN);
#  - sensitive → redacted from plan output / PR comments.
# Desktop: export TF_VAR_pihole_local_dns='["192.168.10.x host", ...]'
variable "pihole_local_dns" {
  description = "Pihole local DNS host records rendered into the chart's addn-hosts ConfigMap key"
  type        = list(string)
  sensitive   = true
}
