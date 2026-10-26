# Real values live in k8s Secret atlantis-app-vars (ns ops), injected as
# TF_VAR_* env via the Atlantis chart's environmentSecrets. Never in this repo.
variable "nfs_media_server" {
  description = "LAN NFS host for media mounts"
  sensitive   = true
}
variable "searxng_secret" {
  description = "SearXNG server.secret_key"
  sensitive   = true
}
variable "webshare_proxy_url" {
  description = "Webshare rotating proxy URL for searxng engine egress"
  sensitive   = true
}
