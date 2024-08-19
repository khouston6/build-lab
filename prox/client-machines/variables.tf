variable "prox_username" {
  description = "Username for Proxmox provider"
  type = string
  sensitive = true
}

variable "prox_password" {
  description = "Password for the Proxmox provider"
  type = string
  sensitive = true
}

variable "prox_copy_user" {
  description = "Username for dedicated Proxmox SCP account"
  type = string
  sensitive = true
}

variable "prox_copy_key" {
  description = "Private key for the dedicated Proxmox SCP account"
  type = string
  sensitive = true
}

variable "vm_user_key" {
  description = "Private key for user created by cloud-init"
  type = string
  sensitive = true
}
