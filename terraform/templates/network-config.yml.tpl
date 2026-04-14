version: 2
ethernets:
  default:
    match:
      name: "en*"
    dhcp4: false
    addresses:
      - ${ip_address}/${prefix_length}
    routes:
      - to: default
        via: ${gateway}
    nameservers:
      addresses:
%{ for dns in split(",", dns_servers) ~}
        - ${trimspace(dns)}
%{ endfor ~}
