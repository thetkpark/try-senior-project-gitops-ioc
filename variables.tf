variable "azure_location" {
  default     = "southeastasia"
  description = "Azure Location"
  type        = string
}

variable "project_name" {
  default     = "senior-project"
  type        = string
  description = "Name of the project"
}

variable "registry_name" {
  default     = "seniorprojectregistry"
  type        = string
  description = "Name of the Azure Container Registry"
}

variable "default_node_config" {
  default = {
    size  = "Standard_B2s"
    count = 1
  }
  type = object({
    size  = string
    count = number
  })
  description = "Default node configuration"
}

