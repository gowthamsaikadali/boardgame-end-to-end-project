variable "client_id" {
  type      = string
  sensitive = true
}

variable "client_secret" {
  type      = string
  sensitive = true
}

variable "tenant_id" {
  type = string
}

variable "subscription_id" {
  type = string
}

variable "prefix" {
  default = "gowtham"
}

variable "location" {
  default = "Canada Central"
}

variable "admin_username" {
  default = "azureuser"
}

variable "ssh_public_key_path" {
  default = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  default = "~/.ssh/id_rsa"
}

variable "vm_size" {
  default = "Standard_D2s_v3"
}

variable "aks_node_count" {
  default = 1
}

variable "aks_vm_size" {
  default = "Standard_D2s_v3"
}

variable "azure_devops_org_url" {
  type = string
}

variable "azure_devops_pat" {
  type      = string
  sensitive = true
}

variable "azure_devops_pool" {
  default = "SelfHostedPool"
}

variable "azure_devops_agent_name" {
  default = "gowtham-agent-01"
}