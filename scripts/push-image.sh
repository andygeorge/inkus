#!/usr/bin/env bash
# Transfer local Docker image(s) into containerd on every Inkus k8s node.
# Default transport is the Incus API (`incus file push` + `incus exec`).
# Pass --ssh to use scp + ssh instead (uses .ssh/inkus + SSH_USER from .env).
#
# Usage:
#   scripts/push-image.sh [--workers-only] [--ssh] IMAGE [IMAGE...]
#
# Examples:
#   scripts/push-image.sh myapp:v1
#   scripts/push-image.sh --workers-only myapp:v1 sidecar:latest
#   scripts/push-image.sh --ssh myapp:v1

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

WORKERS_ONLY=0
USE_SSH=0
IMAGES=()

usage() {
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --workers-only) WORKERS_ONLY=1; shift ;;
        --ssh) USE_SSH=1; shift ;;
        -h|--help) usage 0 ;;
        --) shift; while [ $# -gt 0 ]; do IMAGES+=("$1"); shift; done ;;
        -*) echo "unknown flag: $1" >&2; usage 1 ;;
        *) IMAGES+=("$1"); shift ;;
    esac
done

if [ "${#IMAGES[@]}" -eq 0 ]; then
    echo "error: no images specified" >&2
    usage 1
fi

# --- Preflight ---
if [ ! -f "$REPO_ROOT/.env" ]; then
    echo "error: .env not found — run 'make up' first" >&2
    exit 1
fi
source "$REPO_ROOT/.env"

REQUIRED_BINS=(docker)
if [ "$USE_SSH" -eq 1 ]; then
    REQUIRED_BINS+=(ssh)
else
    REQUIRED_BINS+=(incus)
fi
for bin in "${REQUIRED_BINS[@]}"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "error: '$bin' not found on host" >&2
        exit 1
    fi
done

for img in "${IMAGES[@]}"; do
    if ! docker image inspect "$img" >/dev/null 2>&1; then
        echo "error: local docker image not found: $img" >&2
        exit 1
    fi
done

# --- Derive node list ---
# Incus mode uses instance names; ssh mode uses IPs (same derivation as up.sh).
NETWORK_PREFIX=$(echo "$NETWORK_SUBNET" | cut -d. -f1-3)

NODE_LABELS=()  # for log/summary output
NODE_TARGETS=() # instance names (incus) or IPs (ssh)

if [ "$WORKERS_ONLY" -eq 0 ]; then
    for i in $(seq 0 $((CONTROL_PLANE_COUNT - 1))); do
        NODE_LABELS+=("${CLUSTER_NAME}-cp-${i}")
        if [ "$USE_SSH" -eq 1 ]; then
            NODE_TARGETS+=("${NETWORK_PREFIX}.$((CONTROL_PLANE_IP_START + i))")
        else
            NODE_TARGETS+=("${CLUSTER_NAME}-cp-${i}")
        fi
    done
fi
for i in $(seq 0 $((WORKER_COUNT - 1))); do
    NODE_LABELS+=("${CLUSTER_NAME}-worker-${i}")
    if [ "$USE_SSH" -eq 1 ]; then
        NODE_TARGETS+=("${NETWORK_PREFIX}.$((WORKER_IP_START + i))")
    else
        NODE_TARGETS+=("${CLUSTER_NAME}-worker-${i}")
    fi
done

# --- Mode-specific preflight + transport config ---
if [ "$USE_SSH" -eq 1 ]; then
    SSH_KEY="$REPO_ROOT/.ssh/inkus"
    if [ ! -f "$SSH_KEY" ]; then
        echo "error: ssh key not found at $SSH_KEY — run 'make up' first" >&2
        exit 1
    fi
    SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR)
    # Non-root user → land the tar in /tmp, use sudo for ctr. PID suffix avoids
    # collisions between concurrent runs.
    TAR_REMOTE="/tmp/inkus-push.$$.tar"
else
    # Verify each Incus instance exists and is RUNNING.
    for i in "${!NODE_TARGETS[@]}"; do
        node="${NODE_TARGETS[$i]}"
        state=$(incus list "^${node}\$" --format csv -c s 2>/dev/null || true)
        if [ -z "$state" ]; then
            echo "error: Incus instance not found: $node" >&2
            exit 1
        fi
        if [ "$state" != "RUNNING" ]; then
            echo "error: Incus instance $node is not RUNNING (state=$state)" >&2
            exit 1
        fi
    done
    # incus exec runs as root → write to /root. PID suffix avoids collisions
    # between concurrent runs.
    TAR_REMOTE="/root/inkus-push.$$.tar"
fi

# --- Export once ---
TAR_HOST="$(mktemp -t inkus-push-XXXXXX.tar)"
trap 'rm -f "$TAR_HOST"' EXIT

echo "==> Exporting ${#IMAGES[@]} image(s) with docker save..."
docker save -o "$TAR_HOST" "${IMAGES[@]}"
TAR_SIZE=$(du -h "$TAR_HOST" | cut -f1)
TAR_BYTES=$(stat -c %s "$TAR_HOST")
echo "    tar size: $TAR_SIZE"

# Soft warning — nodes default to 20GiB root disk.
if [ "$TAR_BYTES" -gt $((5 * 1024 * 1024 * 1024)) ]; then
    echo "    warning: tar is >5GiB; check VM_DISK in .env has headroom" >&2
fi

# --- Push + import on each node, sequentially ---
for i in "${!NODE_LABELS[@]}"; do
    label="${NODE_LABELS[$i]}"
    target="${NODE_TARGETS[$i]}"

    if [ "$USE_SSH" -eq 1 ]; then
        echo "==> $label (ssh: ${SSH_USER}@${target})"
        echo "    streaming tar (umask 077)..."
        # umask before cat so the remote file is 0600 from creation — closes
        # the window where /tmp/inkus-push.*.tar would be world-readable.
        ssh "${SSH_OPTS[@]}" "${SSH_USER}@${target}" "umask 077 && cat > ${TAR_REMOTE}" < "$TAR_HOST"
        echo "    importing into containerd (k8s.io namespace)..."
        ssh "${SSH_OPTS[@]}" "${SSH_USER}@${target}" "sudo ctr -n k8s.io images import ${TAR_REMOTE} && rm -f ${TAR_REMOTE}"
    else
        echo "==> $label"
        echo "    pushing tar..."
        incus file push --quiet "$TAR_HOST" "${target}${TAR_REMOTE}"
        echo "    importing into containerd (k8s.io namespace)..."
        incus exec "$target" -- ctr -n k8s.io images import "$TAR_REMOTE"
        incus exec "$target" -- rm -f "$TAR_REMOTE"
    fi
done

# --- Summary ---
echo ""
echo "========================================"
echo " done. image(s) available on:"
for label in "${NODE_LABELS[@]}"; do echo "   - $label"; done
echo ""
echo " containerd registers docker images under docker.io/library/<name>."
echo " in pod specs, set:"
echo "   imagePullPolicy: IfNotPresent   # or: Never"
echo " otherwise kubelet will try to pull from a registry and fail."
echo "========================================"
