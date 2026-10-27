# Central declaration of ALL app namespaces. Adding an app = add its
# namespace here + a module in main.tf.
#
# NOTE: k3s system controllers actively maintain cattle.io/* annotations on
# namespaces — TF would strip them, k3s re-adds them, forever. So the whole
# annotations map is ignored here.
resource "kubernetes_namespace_v1" "audiobookshelf" {
  metadata {
    name = "audiobookshelf"
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_namespace_v1" "searxng" {
  metadata {
    name = "searxng"
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_namespace_v1" "dealchis" {
  metadata {
    name = "dealchis"
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_namespace_v1" "osu_tracker" {
  metadata {
    name = "osu-tracker"
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_namespace_v1" "homeassistant" {
  metadata {
    name = "homeassistant"
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_namespace_v1" "cloudreve" {
  metadata {
    name = "cloudreve"
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_namespace_v1" "firecrawl" {
  metadata {
    name = "firecrawl"
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_namespace_v1" "n8n" {
  metadata {
    name = "n8n"
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}