resource "null_resource" "remote_exec_setup" {
  depends_on = [
    azurerm_linux_virtual_machine.vm,
    azurerm_kubernetes_cluster.aks,
    azurerm_container_registry.acr,
    azurerm_storage_account.storage,
    azurerm_storage_container.tfstate
  ]

  triggers = {
    vm_id            = azurerm_linux_virtual_machine.vm.id
    vm_public_ip     = azurerm_public_ip.pip.ip_address
    acr_login_server = azurerm_container_registry.acr.login_server
    agent_name       = var.azure_devops_agent_name
    org_url          = var.azure_devops_org_url
    pool_name        = var.azure_devops_pool
  }

  connection {
    type        = "ssh"
    user        = var.admin_username
    host        = azurerm_public_ip.pip.ip_address
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "30m"
  }
   provisioner "remote-exec" {
    inline = [
      "echo 'SSH connected successfully'",
      "sudo cloud-init status --wait",                                        
      "sudo systemctl stop unattended-upgrades || true",                      
      "sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock",      
      "sleep 30"                                                              
    ]
  }

  provisioner "file" {
    source      = "${path.module}/scripts/installation.sh"
    destination = "/home/azureuser/installation.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/azureuser/installation.sh",
      "sudo ADMIN_USERNAME='${var.admin_username}' AZDO_ORG_URL='${var.azure_devops_org_url}' AZDO_PAT='${var.azure_devops_pat}' AZDO_POOL='${var.azure_devops_pool}' AZDO_AGENT_NAME='${var.azure_devops_agent_name}' bash /home/azureuser/installation.sh"
    ]
  }
}