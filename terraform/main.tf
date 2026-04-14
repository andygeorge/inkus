terraform {
  required_providers {
    incus = {
      source = "lxc/incus"
    }
  }
}

provider "incus" {}

locals {
  network_prefix = join(".", slice(split(".", var.network_subnet), 0, 3))

  cp_nodes = {
    for i in range(var.control_plane_count) : "${var.cluster_name}-cp-${i}" => {
      ip   = "${local.network_prefix}.${var.control_plane_ip_start + i}"
      role = "controlplane"
    }
  }

  worker_nodes = {
    for i in range(var.worker_count) : "${var.cluster_name}-worker-${i}" => {
      ip   = "${local.network_prefix}.${var.worker_ip_start + i}"
      role = "worker"
    }
  }

  all_nodes = merge(local.cp_nodes, local.worker_nodes)
}

resource "incus_storage_pool" "k8s" {
  name   = var.cluster_name
  driver = "dir"
}

resource "incus_network" "k8s" {
  name = var.cluster_name
  type = "bridge"

  config = {
    "ipv4.address" = "${var.network_gateway}/${var.network_cidr}"
    "ipv4.nat"     = "true"
    "ipv4.dhcp"    = "false"
    "ipv6.address" = "none"
  }
}

resource "incus_profile" "k8s" {
  name = var.cluster_name

  device {
    name = "eth0"
    type = "nic"
    properties = {
      network = incus_network.k8s.name
    }
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      pool = incus_storage_pool.k8s.name
      path = "/"
      size = var.vm_disk
    }
  }
}

resource "incus_instance" "node" {
  for_each = local.all_nodes

  name     = each.key
  image    = "images:ubuntu/24.04/cloud"
  type     = "virtual-machine"
  profiles = [incus_profile.k8s.name]

  config = {
    "limits.cpu"    = var.vm_cpus
    "limits.memory" = var.vm_memory

    "cloud-init.user-data" = templatefile("${path.module}/templates/cloud-init.yml.tpl", {
      hostname       = each.key
      ssh_user       = var.ssh_user
      ssh_public_key = var.ssh_public_key
    })

    "cloud-init.network-config" = templatefile("${path.module}/templates/network-config.yml.tpl", {
      ip_address    = each.value.ip
      prefix_length = var.network_cidr
      gateway       = var.network_gateway
      dns_servers   = var.dns_servers
    })
  }
}
