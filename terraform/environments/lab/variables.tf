
variable "ssh_public_key_file" {
  description = "Path to the SSH public key injected into the VMs"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
variable "proxmox_endpoint" {
  description = "https://srv01.rafaelmellonh.com.br:8006"
  type        = string
  default     = "https://srv01.rafaelmellonh.com.br:8006"
}


variable "templates" {
  description = "Golden image template ID on each node"
  type        = map(number)
  default = {
    srv01 = 9000
    srv02 = 9001
  }
}

variable "network" {
  description = "Lab network settings"
  type = object({
    prefix      = string
    gateway     = string
    domain      = string
    dns_servers = list(string)
  })
  default = {
    prefix      = "192.168.2"
    gateway     = "192.168.2.1"
    domain      = "rafaelmellonh.com.br"
    dns_servers = ["192.168.2.185", "8.8.8.8"]
  }
}


variable "ssh_public_key" {
  description = "Path to the SSH public key injected into the VMs"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "vms" {
  description = "Lab virtual machines"
  type = map(object({
    node   = string
    vm_id  = number
    cores  = number
    memory = number
    disk   = number
    tags   = list(string)
  }))
  default = {
    "mgmt-01"       = { node = "srv01", vm_id = 180, cores = 2, memory = 2048, disk = 30, tags = ["mgmt"] }
    "zbx-01"        = { node = "srv01", vm_id = 181, cores = 2, memory = 4096, disk = 50, tags = ["monitoring"] }
    "k8s-cp-01"     = { node = "srv01", vm_id = 182, cores = 2, memory = 4096, disk = 40, tags = ["k8s"] }
    "k8s-worker-01" = { node = "srv02", vm_id = 183, cores = 4, memory = 10240, disk = 100, tags = ["k8s"] }
    "k8s-worker-02" = { node = "srv02", vm_id = 184, cores = 4, memory = 10240, disk = 100, tags = ["k8s"] }
  }
}
