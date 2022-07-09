resource "kubernetes_namespace" "argocd-namespace" {
  metadata {
    name = "argocd"
  }
  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster
  ]
}

data "http" "argocd-yaml" {
  url = "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
}

data "kubectl_file_documents" "argocd" {
  content = data.http.argocd-yaml.response_body
}

resource "kubectl_manifest" "argocd" {
  override_namespace = kubernetes_namespace.argocd-namespace.metadata[0].name
  count              = length(data.kubectl_file_documents.argocd.documents)
  yaml_body          = element(data.kubectl_file_documents.argocd.documents, count.index)
  depends_on = [
    kubernetes_namespace.argocd-namespace
  ]
}

// ArgoCD Applications

data "kubectl_path_documents" "argocd-apps" {
  pattern = "./argocd/*.yaml"
}

resource "kubectl_manifest" "argocd-apps" {
  override_namespace = kubernetes_namespace.argocd-namespace.metadata[0].name
  for_each           = toset(data.kubectl_path_documents.argocd-apps.documents)
  yaml_body          = each.value
}
