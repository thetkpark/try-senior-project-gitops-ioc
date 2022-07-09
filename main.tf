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
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.1.0"
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
  # Configuration options
  features {

  }
}

resource "azurerm_resource_group" "senior-project-test-rg" {
  name     = "senior-project-test-rg"
  location = "southeastasia"
}

resource "azurerm_container_registry" "senior-project-test-registry" {
  name                = "seniorprojecttestregistry"
  resource_group_name = azurerm_resource_group.senior-project-test-rg.name
  location            = azurerm_resource_group.senior-project-test-rg.location
  sku                 = "Basic"
}

resource "azurerm_kubernetes_cluster" "senior-project-test-aks" {
  name                              = "senior-project-test-aks"
  resource_group_name               = azurerm_resource_group.senior-project-test-rg.name
  location                          = azurerm_resource_group.senior-project-test-rg.location
  role_based_access_control_enabled = true
  dns_prefix                        = "senior-project-test-aks"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_B2s"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "aks-acr-role-assignment" {
  principal_id                     = azurerm_kubernetes_cluster.senior-project-test-aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.senior-project-test-registry.id
  skip_service_principal_aad_check = true
  depends_on = [
    azurerm_kubernetes_cluster.senior-project-test-aks,
    azurerm_container_registry.senior-project-test-registry
  ]
}


provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.senior-project-test-aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.senior-project-test-aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.senior-project-test-aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.senior-project-test-aks.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.senior-project-test-aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.senior-project-test-aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.senior-project-test-aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.senior-project-test-aks.kube_config.0.cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = azurerm_kubernetes_cluster.senior-project-test-aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.senior-project-test-aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.senior-project-test-aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.senior-project-test-aks.kube_config.0.cluster_ca_certificate)
  load_config_file       = false
}

resource "kubernetes_namespace" "argocd-namespace" {
  metadata {
    name = "argocd"
  }
  depends_on = [
    azurerm_kubernetes_cluster.senior-project-test-aks
  ]
}

data "http" "argocd-yaml" {
  url = "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
}

data "kubectl_file_documents" "argocd-yaml" {
    content = data.http.argocd-yaml.response_body
}

resource "kubectl_manifest" "argocd" {
  # yaml_body = data.kubectl_file_documents.argocd-yaml.manifests
  override_namespace = kubernetes_namespace.argocd-namespace.metadata[0].name

  count     = length(data.kubectl_file_documents.argocd-yaml.documents)
  yaml_body = element(data.kubectl_file_documents.argocd-yaml.documents, count.index)
  depends_on = [
    kubernetes_namespace.argocd-namespace
  ]
}