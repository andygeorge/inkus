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
2. copies `example.env` → `.env` if `.env` is missing
3. generates `terraform/terraform.auto.tfvars` from `.env`
4. runs `terraform init` + `terraform apply` to create Incus resources and VMs
5. sets iptables NAT rules for the Incus bridge
6. derives node IPs from config and waits for SSH readiness on all VMs
7. generates `ansible/inventory.ini` from the computed IPs
8. runs the ansible playbook (common -> controlplane -> worker)
9. prints kubeconfig path

## How `make down` Works

1. runs `terraform destroy` if state exists
2. brute-force deletes any orphaned Incus instances, profile, network, and storage pool matching the cluster name
3. removes generated files (kubeconfig, inventory, tfvars)

## Design Decisions

- **static IPs via cloud-init** — DHCP is disabled on the Incus network; IPs are assigned in cloud-init network-config so the API server address is predictable for kubeadm
- **SSH keypair per project** — generated in `.ssh/inkus`, gitignored, used by ansible and the SSH wait loop
- **idempotent** — prereqs check before install, terraform is naturally idempotent, ansible roles guard on existing files (`/etc/kubernetes/admin.conf`, `/etc/kubernetes/kubelet.conf`, flannel daemonset)
- **single config source** — `.env` drives everything; `example.env` is the checked-in template, `.env` is gitignored. `terraform.auto.tfvars` and `ansible/inventory.ini` are generated at runtime
