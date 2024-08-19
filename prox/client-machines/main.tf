
# Define the providers needed for this deployment

terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "3.0.1-rc3"
    }
    ansible = {
      source = "ansible/ansible"
      version = "1.3.0"
    }
    local = {
      source = "hashicorp/local"
      version = "2.5.1"
    }
    null = {
      source = "hashicorp/null"
      version = "3.2.2"
    }
  }
}

# See documentation for Telmate/proxmox provider for permissions needed

provider "proxmox" {
  pm_api_url	= "https://192.168.0.160:8006/api2/json"
  pm_user	= var.prox_username
  pm_password	= var.prox_password
  pm_tls_insecure = true
}

# Define VMs to deploy.  A cloud-init image of the desired image needs to already exist on your Proxmox server.

locals {
  vms = {
    vm1 = {
      name = "alma8-clone"
      clone = "alma8-template"
      ip = "ip=192.168.0.230/24,gw=192.168.0.1"
    }
    vm2 = {
      name = "alma9-clone"
      clone = "alma9-template"
      ip = "ip=192.168.0.231/24,gw=192.168.0.1"
    }
    vm3 = {
      name = "fedora37-clone"
      clone = "fedora37-template"
      ip = "ip=192.168.0.232/24,gw=192.168.0.1"
    }
  }
}

# Point to local cloud-config template

data "local_file" "cloud_init_file_local" {
  filename = "/build-lab/prox/cloud-init-files/cloud-config"
}

# Use null_resource to connect to Proxmox server over SSH, then copy cloud-config file to available storage.

resource "null_resource" "cloud_init_config" {
  connection {
    type = "ssh"
    user = var.prox_copy_user
    private_key = file(var.prox_copy_key)
    host = "192.168.0.160"
  }
  provisioner "file" {
    source = data.local_file.cloud_init_file_local.filename
    destination = "/mnt/pve/images/snippets/user_data.yml"
  }
}

# Define the settings for the deployment.

resource "proxmox_vm_qemu" "cloudinit" {
  depends_on = [
    null_resource.cloud_init_config,
  ]

  for_each = local.vms
  name = each.value.name
  desc = each.value.name
  target_node = "pve"
  clone = each.value.clone
  agent = 1

  cores = 2
  sockets = 1
  memory = 4096
  
  bios = "ovmf" # UEFI
  scsihw = "virtio-scsi-single"
  
  os_type = "cloud-init"
  ipconfig0 = each.value.ip
  
  cicustom = "user=images:snippets/user_data.yml"

  disks {
    scsi {
      scsi0 {
        disk {
          cache = "writeback"
          discard = true
          iothread = true
          size = "32G"
          storage = "ssd1tbthin"
        }
      }
    }  
    ide {
      ide3 {
        cloudinit {
          storage = "images"
        }
      }
    }
  }

  efidisk {
    efitype = "4m"
    storage = "ssd1tbthin"
  }

  network {
    model = "virtio"
    bridge = "vmbr0"
  }
}

# https://stackoverflow.com/questions/45489534/best-way-currently-to-create-an-ansible-inventory-from-terraform

resource "local_file" "inventory" {
  content = templatefile("/build-lab/prox/client-machines/templates/inventory.cfg",
    {
      vm_ips = values(proxmox_vm_qemu.cloudinit)[*].default_ipv4_address
    }
  )
  filename = "/build-lab/prox/ansible/inventory.ini"
}

resource "ansible_playbook" "keys" {
  for_each = proxmox_vm_qemu.cloudinit
  playbook = "/build-lab/prox/ansible/collect-keys.yaml"
  name = each.value.default_ipv4_address
  replayable = true
}

resource "ansible_playbook" "disable_cloudinit" {
  depends_on = [
    ansible_playbook.keys,
  ]
  for_each = proxmox_vm_qemu.cloudinit
  playbook = "/build-lab/prox/ansible/disable-cloudinit.yaml"
  name = each.value.default_ipv4_address

  extra_vars = {
    ssh_key = var.vm_user_key
  }
}

