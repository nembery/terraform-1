#-----------------------------------------------------------------------------------------------------------------
# Create resource group for FWs, FW NICs, and FW LBs

resource "azurerm_resource_group" "common_fw" {
  name     = "${var.global_prefix}${var.fw_prefix}-rg"
  location = var.location
}

#-----------------------------------------------------------------------------------------------------------------
# Create storage account and file share for bootstrapping

resource "random_string" "main" {
  length      = 15
  min_lower   = 5
  min_numeric = 10
  special     = false
}

resource "azurerm_storage_account" "main" {
  name                     = random_string.main.result
  account_tier             = "Standard"
  account_replication_type = "LRS"
  location                 = azurerm_resource_group.common_fw.location
  resource_group_name      = azurerm_resource_group.common_fw.name
}

module "common_fileshare" {
  source               = "./modules/azure_bootstrap/"
  name                 = "${var.fw_prefix}-bootstrap"
  quota                = 1
  storage_account_name = azurerm_storage_account.main.name
  storage_account_key  = azurerm_storage_account.main.primary_access_key
  local_file_path        = "bootstrap_files/"
}


#-----------------------------------------------------------------------------------------------------------------
# Create VM-Series.  For every fw_name entered, an additional VM-Series instance will be deployed.

module "common_fw" {
  source                    = "./modules/vmseries/"
  name                      = "${var.fw_prefix}-vm"
  vm_count                  = var.fw_count
  username                  = var.fw_username
  password                  = var.fw_password
  panos                     = var.fw_panos
  license                   = var.fw_license
  nsg_prefix                = var.fw_nsg_prefix
  avset_name                = "${var.fw_prefix}-avset"
  subnet_mgmt               = module.vnet.vnet_subnets[0]
  subnet_untrust            = module.vnet.vnet_subnets[1]
  subnet_trust              = module.vnet.vnet_subnets[2]
  nic0_public_ip            = true
  nic1_public_ip            = true
  nic2_public_ip            = false
  nic1_backend_pool_ids     = [module.common_extlb.backend_pool_id]
  nic2_backend_pool_ids     = [module.common_intlb.backend_pool_id]
  bootstrap_storage_account = azurerm_storage_account.main.name
  bootstrap_access_key      = azurerm_storage_account.main.primary_access_key
  bootstrap_file_share      = module.common_fileshare.file_share_name
  bootstrap_share_directory = "None"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.common_fw.name
  
  dependencies = [
    module.common_fileshare.completion
  ]
}

#-----------------------------------------------------------------------------------------------------------------
# Create public load balancer.  Load balancer uses firewall's untrust interfaces as its backend pool.

module "common_extlb" {
  source                  = "./modules/lb/"
  name                    = "${var.fw_prefix}-public-lb"
  type                    = "public"
  sku                     = "Standard"
  probe_ports             = [22]
  frontend_ports          = [80, 22, 443]
  backend_ports           = [80, 22, 443]
  protocol                = "Tcp"
  location                = var.location
  resource_group_name     = azurerm_resource_group.common_fw.name
}

#-----------------------------------------------------------------------------------------------------------------
# Create internal load balancer. Load balancer uses firewall's trust interfaces as its backend pool

module "common_intlb" {
  source                  = "./modules/lb/"
  name                    = "${var.fw_prefix}-internal-lb"
  type                    = "private"
  sku                     = "Standard"
  probe_ports             = [22]
  frontend_ports          = [0]
  backend_ports           = [0]
  protocol                = "All"
  subnet_id               = module.vnet.vnet_subnets[2]
  private_ip_address      = var.fw_internal_lb_ip
  location                = var.location
  resource_group_name     = azurerm_resource_group.common_fw.name
}

#-----------------------------------------------------------------------------------------------------------------
# Outputs to terminal

output EXT-LB {
  value = "http://${module.common_extlb.public_ip[0]}"
}

output MGMT-FW1 {
  value = "https://${module.common_fw.nic0_public_ip[0]}"
}

output MGMT-FW2 {
  value = "https://${module.common_fw.nic0_public_ip[1]}"
}

output SSH-TO-SPOKE2 {
  value = "ssh ${var.spoke_username}@${module.common_extlb.public_ip[0]}"
}
