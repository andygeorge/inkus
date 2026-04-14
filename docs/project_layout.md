## Project Layout

```
example.env                             # default config template (checked in)
.env                                    # your local config (gitignored, copied from example.env)
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

Generated (gitignored): `.env`, `.ssh/`, `kubeconfig`, `terraform/terraform.auto.tfvars`, `terraform/.terraform/`, `terraform/terraform.tfstate*`, `ansible/inventory.ini`
