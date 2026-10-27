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

module "dealchis" {
  source    = "./modules/dealchis"
  namespace = kubernetes_namespace_v1.dealchis.metadata[0].name
}

module "osu_tracker" {
  source              = "./modules/osu-tracker"
  namespace           = kubernetes_namespace_v1.osu_tracker.metadata[0].name
  osu_mongodb_uri     = var.osu_mongodb_uri
  osu_client_secret   = var.osu_client_secret
  osu_session_secret  = var.osu_session_secret
}

module "homeassistant" {
  source    = "./modules/homeassistant"
  namespace = kubernetes_namespace_v1.homeassistant.metadata[0].name
}

module "cloudreve" {
  source            = "./modules/cloudreve"
  namespace         = kubernetes_namespace_v1.cloudreve.metadata[0].name
  nfs_media_server  = var.nfs_media_server
}

module "firecrawl" {
  source    = "./modules/firecrawl"
  namespace = kubernetes_namespace_v1.firecrawl.metadata[0].name
}

module "n8n" {
  source    = "./modules/n8n"
  namespace = kubernetes_namespace_v1.n8n.metadata[0].name
}

module "paloch" {
  source    = "./modules/paloch"
  namespace = kubernetes_namespace_v1.paloch.metadata[0].name
}

module "vocard" {
  source    = "./modules/vocard"
  namespace = kubernetes_namespace_v1.vocard.metadata[0].name
}

module "omniroute" {
  source    = "./modules/omniroute"
  namespace = kubernetes_namespace_v1.omniroute.metadata[0].name
}

module "auto_school" {
  source    = "./modules/auto-school"
  namespace = kubernetes_namespace_v1.auto_school.metadata[0].name
}
