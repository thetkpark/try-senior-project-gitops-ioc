terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.13.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.12.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    http = {
      source = "hashicorp/http"
      version = "2.2.0"
    }
  }
}

provider "azurerm" {
  features {

  }
}

resource "azurerm_resource_group" "resource_group" {
  name     = "${var.project_name}-rg"
  location = var.azure_location
}

resource "azurerm_container_registry" "container_registry" {
  name                = var.registry_name
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  sku                 = "Basic"
}

resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                              = "${var.project_name}-aks"
  resource_group_name               = azurerm_resource_group.resource_group.name
  location                          = azurerm_resource_group.resource_group.location
  role_based_access_control_enabled = true
  dns_prefix                        = var.project_name

  default_node_pool {
    name       = "default"
    node_count = var.default_node_config.count
    vm_size    = var.default_node_config.size
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "aks-acr-role-assignment" {
  principal_id                     = azurerm_kubernetes_cluster.aks_cluster.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.container_registry.id
  skip_service_principal_aad_check = true
  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster,
    azurerm_container_registry.container_registry
  ]
}


provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks_cluster.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.cluster_ca_certificate)
}

provider "kubectl" {
  host                   = azurerm_kubernetes_cluster.aks_cluster.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.cluster_ca_certificate)
  load_config_file       = false
}

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
  count     = length(data.kubectl_file_documents.argocd.documents)
  yaml_body = element(data.kubectl_file_documents.argocd.documents, count.index)
  depends_on = [
    kubernetes_namespace.argocd-namespace
  ]
}
data "kubectl_path_documents" "argocd-apps" {
    pattern = "./argocd/*.yaml"
}

resource "kubectl_manifest" "argocd-apps" {
    override_namespace = kubernetes_namespace.argocd-namespace.metadata[0].name
    for_each  = toset(data.kubectl_path_documents.argocd-apps.documents)
    yaml_body = each.value
}