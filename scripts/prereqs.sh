#!/usr/bin/env bash
set -euo pipefail

# Linux Mint uses its own codenames (wilma, vera, etc.) but upstream repos
# (HashiCorp, Zabbly, Kubernetes) only publish for Ubuntu codenames.
# Map to the underlying Ubuntu release.
get_ubuntu_codename() {
    local codename
    codename=$(lsb_release -cs)
    # if /etc/upstream-release exists (Mint), use that instead
    if [ -f /etc/upstream-release/lsb-release ]; then
        codename=$(. /etc/upstream-release/lsb-release && echo "${DISTRIB_CODENAME:-$codename}")
    fi
    echo "$codename"
}

UBUNTU_CODENAME="$(get_ubuntu_codename)"

echo "==> Installing host prerequisites... (apt codename: $UBUNTU_CODENAME)"

# Terraform
if ! command -v terraform &>/dev/null; then
    echo "  -> Installing Terraform..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq gnupg software-properties-common
    wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $UBUNTU_CODENAME main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq terraform
else
    echo "  -> Terraform already installed"
fi

# Ansible
if ! command -v ansible &>/dev/null; then
    echo "  -> Installing Ansible..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ansible
else
    echo "  -> Ansible already installed"
fi

# Incus
if ! command -v incus &>/dev/null; then
    echo "  -> Installing Incus..."
    curl -fsSL https://pkgs.zabbly.com/key.asc | sudo gpg --dearmor -o /etc/apt/keyrings/zabbly.gpg 2>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/zabbly.gpg] https://pkgs.zabbly.com/incus/stable $UBUNTU_CODENAME main" | sudo tee /etc/apt/sources.list.d/zabbly-incus-stable.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq incus
    sudo usermod -aG incus-admin "$USER"
    echo ""
    echo "  !! Incus installed. You may need to log out and back in for group membership to take effect."
    echo "  !! Then run: incus admin init --minimal"
    echo ""
else
    echo "  -> Incus already installed"
fi

# kubectl (host-side, for make status)
if ! command -v kubectl &>/dev/null; then
    echo "  -> Installing kubectl..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq kubectl
else
    echo "  -> kubectl already installed"
fi

# Helm
if ! command -v helm &>/dev/null; then
    echo "  -> Installing Helm..."
    curl -fsSL https://baltocdn.com/helm/signing.asc | sudo gpg --dearmor -o /usr/share/keyrings/helm-archive-keyring.gpg 2>/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm-archive-keyring.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq helm
else
    echo "  -> Helm already installed"
fi

echo "==> All prerequisites installed."
