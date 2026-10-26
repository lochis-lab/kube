resource "kubernetes_manifest" "audiobookshelf-deploy" {
  lifecycle { ignore_changes = [object.spec.template.metadata.creationTimestamp] }
  manifest = yamldecode(templatefile("templates/abs-deploy-audiobookshelf.tftpl", {
    nfs_media_server = var.nfs_media_server
    searxng_secret   = var.searxng_secret
    webshare_proxy_url = var.webshare_proxy_url
  }))
}
# import: terraform import kubernetes_manifest.audiobookshelf-deploy apiVersion=apps/v1,kind=Deployment,name=audiobookshelf,namespace=audiobookshelf
resource "kubernetes_manifest" "audiobookshelf-ws-ir" {
  manifest = yamldecode(templatefile("templates/abs-ir-audiobookshelf-ws.tftpl", {
    nfs_media_server = var.nfs_media_server
    searxng_secret   = var.searxng_secret
    webshare_proxy_url = var.webshare_proxy_url
  }))
}
# import: terraform import kubernetes_manifest.audiobookshelf-ws-ir apiVersion=traefik.io/v1alpha1,kind=IngressRoute,name=audiobookshelf-ws,namespace=audiobookshelf
resource "kubernetes_manifest" "audiobookshelf-ir" {
  manifest = yamldecode(templatefile("templates/abs-ir-audiobookshelf.tftpl", {
    nfs_media_server = var.nfs_media_server
    searxng_secret   = var.searxng_secret
    webshare_proxy_url = var.webshare_proxy_url
  }))
}
# import: terraform import kubernetes_manifest.audiobookshelf-ir apiVersion=traefik.io/v1alpha1,kind=IngressRoute,name=audiobookshelf,namespace=audiobookshelf
resource "kubernetes_manifest" "abs-config-pvc" {
  manifest = yamldecode(templatefile("templates/abs-pvc-abs-config.tftpl", {
    nfs_media_server = var.nfs_media_server
    searxng_secret   = var.searxng_secret
    webshare_proxy_url = var.webshare_proxy_url
  }))
}
# import: terraform import kubernetes_manifest.abs-config-pvc apiVersion=v1,kind=PersistentVolumeClaim,name=abs-config,namespace=audiobookshelf
resource "kubernetes_manifest" "abs-metadata-pvc" {
  manifest = yamldecode(templatefile("templates/abs-pvc-abs-metadata.tftpl", {
    nfs_media_server = var.nfs_media_server
    searxng_secret   = var.searxng_secret
    webshare_proxy_url = var.webshare_proxy_url
  }))
}
# import: terraform import kubernetes_manifest.abs-metadata-pvc apiVersion=v1,kind=PersistentVolumeClaim,name=abs-metadata,namespace=audiobookshelf
resource "kubernetes_manifest" "audiobookshelf-config-pvc" {
  manifest = yamldecode(templatefile("templates/abs-pvc-audiobookshelf-config.tftpl", {
    nfs_media_server = var.nfs_media_server
    searxng_secret   = var.searxng_secret
    webshare_proxy_url = var.webshare_proxy_url
  }))
}
# import: terraform import kubernetes_manifest.audiobookshelf-config-pvc apiVersion=v1,kind=PersistentVolumeClaim,name=audiobookshelf-config,namespace=audiobookshelf
resource "kubernetes_manifest" "audiobookshelf-metadata-pvc" {
  manifest = yamldecode(templatefile("templates/abs-pvc-audiobookshelf-metadata.tftpl", {
    nfs_media_server = var.nfs_media_server
    searxng_secret   = var.searxng_secret
    webshare_proxy_url = var.webshare_proxy_url
  }))
}
# import: terraform import kubernetes_manifest.audiobookshelf-metadata-pvc apiVersion=v1,kind=PersistentVolumeClaim,name=audiobookshelf-metadata,namespace=audiobookshelf
resource "kubernetes_manifest" "audiobookshelf-svc" {
  manifest = yamldecode(templatefile("templates/abs-svc-audiobookshelf.tftpl", {
    nfs_media_server = var.nfs_media_server
    searxng_secret   = var.searxng_secret
    webshare_proxy_url = var.webshare_proxy_url
  }))
}
# import: terraform import kubernetes_manifest.audiobookshelf-svc apiVersion=v1,kind=Service,name=audiobookshelf,namespace=audiobookshelf
resource "kubernetes_manifest" "searxng-settings-cm" {
  manifest = yamldecode(templatefile("templates/searxng-cm-searxng-settings.tftpl", {
    nfs_media_server = var.nfs_media_server
    searxng_secret   = var.searxng_secret
    webshare_proxy_url = var.webshare_proxy_url
  }))
}
# import: terraform import kubernetes_manifest.searxng-settings-cm apiVersion=v1,kind=ConfigMap,name=searxng-settings,namespace=searxng
resource "kubernetes_manifest" "searxng-deploy" {
  manifest = yamldecode(templatefile("templates/searxng-deploy-searxng.tftpl", {
    nfs_media_server = var.nfs_media_server
    searxng_secret   = var.searxng_secret
    webshare_proxy_url = var.webshare_proxy_url
  }))
}
# import: terraform import kubernetes_manifest.searxng-deploy apiVersion=apps/v1,kind=Deployment,name=searxng,namespace=searxng
resource "kubernetes_manifest" "searxng" {
  manifest = yamldecode(templatefile("templates/searxng-ns-searxng.tftpl", {
    nfs_media_server = var.nfs_media_server
    searxng_secret   = var.searxng_secret
    webshare_proxy_url = var.webshare_proxy_url
  }))
}
# import: terraform import kubernetes_manifest.searxng apiVersion=v1,kind=Namespace,name=searxng
resource "kubernetes_manifest" "searxng-svc" {
  manifest = yamldecode(templatefile("templates/searxng-svc-searxng.tftpl", {
    nfs_media_server = var.nfs_media_server
    searxng_secret   = var.searxng_secret
    webshare_proxy_url = var.webshare_proxy_url
  }))
}
# import: terraform import kubernetes_manifest.searxng-svc apiVersion=v1,kind=Service,name=searxng,namespace=searxng
