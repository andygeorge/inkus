# Inkus

Inkus is an ***EXTREMELY-VIBECODED*** [Incus](https://github.com/lxc/incus) VM-based, minimal Kubernetes cluster, provisioned with Terraform, configured with Ansible, and bootstrapped with kubeadm. The entire stack is brought up or torn down by a single command.

## Prerequisites

- Linux Mint, Ubuntu, or Debian host
- `make prereqs` installs everything else: Terraform, Ansible, Incus, kubectl, and Helm

## Quick Start

```bash
# edit .env if you want to change cluster size, network, k8s version, etc.
# (first run copies example.env → .env automatically)
cp example.env .env
vim .env

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

## Environment Variables

`.env` is the **only file you need to edit**. All terraform variables, ansible inventory, cloud-init templates, and IP assignments are derived from it. If `.env` doesn't exist, `make up` copies [`example.env`](./example.env) to create one with sensible defaults.

## Documentation

Additional documentation in [`docs`](docs/):

- [Stack](docs/stack.md) (Clod-generated)
- [Project Layout](docs/project_layout.md) (Clod-generated)
