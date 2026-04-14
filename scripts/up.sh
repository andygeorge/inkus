#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Generate .env from example.env if it doesn't exist
if [ ! -f "$REPO_ROOT/.env" ]; then
    echo "==> No .env found — copying from example.env..."
    cp "$REPO_ROOT/example.env" "$REPO_ROOT/.env"
fi

source "$REPO_ROOT/.env"

echo "========================================"
echo " Inkus — bringing up cluster"
echo "========================================"

# --- SSH keypair ---
SSH_DIR="$REPO_ROOT/.ssh"
SSH_KEY="$SSH_DIR/inkus"
if [ ! -f "$SSH_KEY" ]; then
    echo "==> Generating SSH keypair..."
    mkdir -p "$SSH_DIR"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "inkus"
fi
SSH_PUB=$(cat "$SSH_KEY.pub")

# --- Generate terraform.auto.tfvars ---
echo "==> Generating terraform variables..."
cat > "$REPO_ROOT/terraform/terraform.auto.tfvars" <<EOF
cluster_name           = "$CLUSTER_NAME"
k8s_version            = "$K8S_VERSION"
network_subnet         = "$NETWORK_SUBNET"
network_cidr           = $NETWORK_CIDR
network_gateway        = "$NETWORK_GATEWAY"
dns_servers            = "$DNS_SERVERS"
control_plane_count    = $CONTROL_PLANE_COUNT
worker_count           = $WORKER_COUNT
control_plane_ip_start = $CONTROL_PLANE_IP_START
worker_ip_start        = $WORKER_IP_START
vm_cpus                = $VM_CPUS
vm_memory              = "$VM_MEMORY"
vm_disk                = "$VM_DISK"
ssh_user               = "$SSH_USER"
ssh_public_key         = "$SSH_PUB"
EOF

# --- Terraform ---
echo "==> Running Terraform..."
cd "$REPO_ROOT/terraform"
terraform init -input=false
terraform apply -auto-approve -input=false
cd "$REPO_ROOT"

# --- Fix NAT forwarding ---
# Incus creates nft rules for the bridge but libvirt/docker set iptables FORWARD
# policy to DROP, and iptables-nft doesn't jump to the incus nft chains. Add
# explicit iptables rules so VM traffic can reach the internet.
echo "==> Ensuring NAT forwarding for $CLUSTER_NAME bridge..."
if ! sudo iptables -C FORWARD -i "$CLUSTER_NAME" -j ACCEPT 2>/dev/null; then
    sudo iptables -I FORWARD -i "$CLUSTER_NAME" -j ACCEPT
fi
if ! sudo iptables -C FORWARD -o "$CLUSTER_NAME" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
    sudo iptables -I FORWARD -o "$CLUSTER_NAME" -m state --state RELATED,ESTABLISHED -j ACCEPT
fi
if ! sudo iptables -t nat -C POSTROUTING -s "${NETWORK_SUBNET}/${NETWORK_CIDR}" ! -d "${NETWORK_SUBNET}/${NETWORK_CIDR}" -j MASQUERADE 2>/dev/null; then
    sudo iptables -t nat -A POSTROUTING -s "${NETWORK_SUBNET}/${NETWORK_CIDR}" ! -d "${NETWORK_SUBNET}/${NETWORK_CIDR}" -j MASQUERADE
fi

# --- Derive IPs ---
NETWORK_PREFIX=$(echo "$NETWORK_SUBNET" | cut -d. -f1-3)

declare -a CP_IPS=()
for i in $(seq 0 $((CONTROL_PLANE_COUNT - 1))); do
    CP_IPS+=("${NETWORK_PREFIX}.$((CONTROL_PLANE_IP_START + i))")
done

declare -a WORKER_IPS=()
for i in $(seq 0 $((WORKER_COUNT - 1))); do
    WORKER_IPS+=("${NETWORK_PREFIX}.$((WORKER_IP_START + i))")
done

ALL_IPS=("${CP_IPS[@]}" "${WORKER_IPS[@]}")

# --- Wait for SSH ---
echo "==> Waiting for VMs to accept SSH connections..."
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"
for ip in "${ALL_IPS[@]}"; do
    printf "  -> %s " "$ip"
    retries=0
    until ssh $SSH_OPTS -i "$SSH_KEY" "${SSH_USER}@${ip}" true 2>/dev/null; do
        retries=$((retries + 1))
        if [ "$retries" -ge 60 ]; then
            echo "FAILED (timeout)"
            exit 1
        fi
        printf "."
        sleep 5
    done
    echo " ok"
done

# --- Generate Ansible inventory ---
echo "==> Generating Ansible inventory..."
INVENTORY="$REPO_ROOT/ansible/inventory.ini"

cat > "$INVENTORY" <<EOF
[controlplane]
EOF
for i in $(seq 0 $((CONTROL_PLANE_COUNT - 1))); do
    echo "${CLUSTER_NAME}-cp-${i} ansible_host=${CP_IPS[$i]}" >> "$INVENTORY"
done

cat >> "$INVENTORY" <<EOF

[workers]
EOF
for i in $(seq 0 $((WORKER_COUNT - 1))); do
    echo "${CLUSTER_NAME}-worker-${i} ansible_host=${WORKER_IPS[$i]}" >> "$INVENTORY"
done

cat >> "$INVENTORY" <<EOF

[all:vars]
ansible_user=${SSH_USER}
ansible_ssh_private_key_file=${SSH_KEY}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
k8s_version=${K8S_VERSION}
ssh_user=${SSH_USER}
EOF

# --- Ansible ---
echo "==> Running Ansible playbook..."
cd "$REPO_ROOT/ansible"
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini playbook.yml -v
cd "$REPO_ROOT"

# --- Done ---
echo ""
echo "========================================"
echo " Inkus cluster is UP"
echo "========================================"
echo ""
echo "kubeconfig: $REPO_ROOT/kubeconfig"
echo ""
echo "  export KUBECONFIG=$REPO_ROOT/kubeconfig"
echo "  kubectl get nodes"
echo ""
echo "or: make status"
