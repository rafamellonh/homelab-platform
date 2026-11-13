data "proxmox_virtual_environment_nodes" "all" {}

output "nodes" {
  value = data.proxmox_virtual_environment_nodes.all.names
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name      = each.key
  node_name = each.value.node
  vm_id     = each.value.vm_id
  tags      = concat(each.value.tags, ["terraform"])

  clone {
    vm_id = var.templates[each.value.node]
    full  = true
  }

  cpu {
    cores = each.value.cores
    type  = "x86-64-v3"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk
  }

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.network.prefix}.${each.value.vm_id}/24"
        gateway = var.network.gateway
      }
    }

    dns {
      domain  = var.network.domain
      servers = var.network.dns_servers
    }

    user_account {
      username = "rafael"
      keys     = [trimspace(file(var.ssh_public_key_file))]
    }
  }
}


output "vms" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm : name => {
      node   = vm.node_name
      vm_id  = vm.vm_id
      cores  = vm.cpu[0].cores
      memory = vm.memory[0].dedicated
      disk   = vm.disk[0].size
      ips    = [for ip in flatten(vm.ipv4_addresses) : ip if ip != "127.0.0.1"]
    }
  }
}