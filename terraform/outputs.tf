output "control_plane_ips" {
  value = { for name, node in local.cp_nodes : name => node.ip }
}

output "worker_ips" {
  value = { for name, node in local.worker_nodes : name => node.ip }
}

output "all_node_ips" {
  value = { for name, node in local.all_nodes : name => node.ip }
}
