#cloud-config
hostname: ${hostname}
manage_etc_hosts: true
users:
  - name: ${ssh_user}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_public_key}
package_update: true
packages:
  - openssh-server
  - curl
  - apt-transport-https
  - ca-certificates
  - gnupg
