variable "cluster_name" {
  type    = string
  default = "inkus"
}

variable "k8s_version" {
  type    = string
  default = "1.31"
}

variable "network_subnet" {
  type    = string
  default = "10.0.100.0"
}

variable "network_cidr" {
  type    = number
  default = 24
}

variable "network_gateway" {
  type    = string
  default = "10.0.100.1"
}

variable "dns_servers" {
  type    = string
  default = "8.8.8.8,8.8.4.4"
}

variable "control_plane_count" {
  type    = number
  default = 1
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "control_plane_ip_start" {
  type    = number
  default = 10
}

variable "worker_ip_start" {
  type    = number
  default = 20
}

variable "vm_cpus" {
  type    = number
  default = 2
}

variable "vm_memory" {
  type    = string
  default = "2GiB"
}

variable "vm_disk" {
  type    = string
  default = "20GiB"
}

variable "ssh_user" {
  type    = string
  default = "k8s"
}

variable "ssh_public_key" {
  type        = string
  description = "Public SSH key injected into VMs via cloud-init"
}
