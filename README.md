# Inkus

Inkus is an opinionated local Kubernetes cluster running on Incus VMs, provisioned with Terraform, configured with Ansible, and bootstrapped with kubeadm. The entire stack is brought up or torn down by a single command.

## Prerequisites

- Linux Mint, Ubuntu, or Debian host
- `make prereqs` installs everything else: Terraform, Ansible, Incus, and kubectl

## Quick Start

```bash
# edit config.env if you want to change cluster size, network, k8s version, etc.
vim config.env

# bring up the cluster (installs prereqs, provisions VMs, configures k8s)
make up

# verify
make status

# tear down
make down
```

After `make up`, a `kubeconfig` file is written to the repo root. Use it with:

```bash
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

## Commands

| Command | Description |
|---------|-------------|
| `make up` | install prereqs + provision VMs + configure k8s + fetch kubeconfig |
| `make down` | terraform destroy + brute-force Incus cleanup + remove generated files |
| `make status` | `kubectl get nodes` using local kubeconfig |
| `make prereqs` | install host prerequisites only |
| `make clean` | `make down` + remove .terraform state and .ssh keys |

## Configuration

`config.env` is the **only file you need to edit**. All terraform variables, ansible inventory, cloud-init templates, and IP assignments are derived from it.

```bash
CLUSTER_NAME=inkus               # Incus resources, VM hostnames, bridge name
K8S_VERSION=1.31                 # kubernetes major.minor version
NETWORK_SUBNET=10.0.100.0        # VM network subnet
NETWORK_CIDR=24                  # subnet mask
NETWORK_GATEWAY=10.0.100.1       # Incus bridge gateway
DNS_SERVERS="8.8.8.8,8.8.4.4"   # DNS servers injected into VMs
CONTROL_PLANE_COUNT=1            # number of control plane nodes
WORKER_COUNT=2                   # number of worker nodes
CONTROL_PLANE_IP_START=10        # CP nodes get .10, .11, ...
WORKER_IP_START=20               # workers get .20, .21, ...
VM_CPUS=2                        # vCPUs per VM
VM_MEMORY=2GiB                   # memory per VM
VM_DISK=20GiB                    # disk per VM
SSH_USER=k8s                     # user created in VMs via cloud-init
```

## Stack

- **Terraform + [Incus provider](https://registry.terraform.io/providers/lxc/incus/)** — provisions storage pool, bridge network (static IPs, no DHCP), VM profile, and `ubuntu/24.04/cloud` VMs with cloud-init
- **Cloud-init** — first-boot config: hostname, SSH user with sudo, static IP via netplan, base packages
- **Ansible** — three roles applied in order:
  - `common` — disables swap, loads kernel modules (`overlay`, `br_netfilter`), sets sysctls, installs and configures containerd (with SystemdCgroup), installs kubeadm/kubelet/kubectl
  - `controlplane` — runs `kubeadm init`, deploys Flannel CNI (`10.244.0.0/16`), generates join token, fetches kubeconfig to host
  - `worker` — runs `kubeadm join` using the token from the control plane
- **Flannel** — vxlan-based CNI applied from the upstream release manifest

## How `make up` Works

1. generates an ed25519 SSH keypair in `.ssh/inkus` (if missing)
2. generates `terraform/terraform.auto.tfvars` from `config.env`
3. runs `terraform init` + `terraform apply` to create Incus resources and VMs
4. sets iptables NAT rules for the Incus bridge
5. derives node IPs from config and waits for SSH readiness on all VMs
6. generates `ansible/inventory.ini` from the computed IPs
7. runs the ansible playbook (common -> controlplane -> worker)
8. prints kubeconfig path

## How `make down` Works

1. runs `terraform destroy` if state exists
2. brute-force deletes any orphaned Incus instances, profile, network, and storage pool matching the cluster name
3. removes generated files (kubeconfig, inventory, tfvars)

## Design Decisions

- **static IPs via cloud-init** — DHCP is disabled on the Incus network; IPs are assigned in cloud-init network-config so the API server address is predictable for kubeadm
- **SSH keypair per project** — generated in `.ssh/inkus`, gitignored, used by ansible and the SSH wait loop
- **idempotent** — prereqs check before install, terraform is naturally idempotent, ansible roles guard on existing files (`/etc/kubernetes/admin.conf`, `/etc/kubernetes/kubelet.conf`, flannel daemonset)
- **single config source** — `config.env` drives everything; `terraform.auto.tfvars` and `ansible/inventory.ini` are generated at runtime

## Project Layout

```
config.env                              # the only file you edit
Makefile                                # entry point for all operations
scripts/
  up.sh                                 # full orchestration: provision + configure
  down.sh                               # teardown + cleanup
  prereqs.sh                            # install host dependencies
terraform/
  main.tf                               # Incus infra: pool, network, profile, VMs
  variables.tf                          # terraform variable definitions
  outputs.tf                            # node IP outputs
  templates/
    cloud-init.yml.tpl                  # VM user-data template
    network-config.yml.tpl              # VM netplan template
ansible/
  playbook.yml                          # 3 plays: common, controlplane, worker
  roles/
    common/tasks/main.yml               # shared node config
    common/handlers/main.yml            # service restart handlers
    controlplane/tasks/main.yml         # kubeadm init + flannel + kubeconfig
    worker/tasks/main.yml               # kubeadm join
```

Generated (gitignored): `.ssh/`, `kubeconfig`, `terraform/terraform.auto.tfvars`, `terraform/.terraform/`, `terraform/terraform.tfstate*`, `ansible/inventory.ini`
