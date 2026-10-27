module "audiobookshelf" {
  source            = "./modules/audiobookshelf"
  namespace         = kubernetes_namespace_v1.audiobookshelf.metadata[0].name
  nfs_media_server  = var.nfs_media_server
}

module "searxng" {
  source             = "./modules/searxng"
  namespace          = kubernetes_namespace_v1.searxng.metadata[0].name
  searxng_secret     = var.searxng_secret
  webshare_proxy_url = var.webshare_proxy_url
}
