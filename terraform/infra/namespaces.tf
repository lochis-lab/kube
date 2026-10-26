resource "kubernetes_namespace" "ops" {
  metadata {
    name = "ops"
    labels = { managed_by = "terraform", repo = "kube" }
  }
}
