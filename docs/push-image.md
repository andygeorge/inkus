## Pushing Local Docker Images to Nodes

When you're iterating on an image locally and don't want to stand up a registry, `make push-image` exports the image from the host Docker daemon and imports it into containerd's `k8s.io` namespace on every node.

Default transport is the Incus API (`incus file push` + `incus exec`) — no SSH required. Pass `SSH=1` to use `scp` + `ssh` instead (keyed off `.ssh/inkus` and `SSH_USER` from `.env`).

## Usage

```bash
# one image, all nodes
make push-image IMAGE=myapp:v1

# multiple images in a single export
make push-image IMAGES="myapp:v1 sidecar:latest"

# workers only (skip control-plane — usually what you want)
make push-image WORKERS_ONLY=1 IMAGE=myapp:v1

# use ssh instead of the Incus API
make push-image SSH=1 IMAGE=myapp:v1

# flags compose
make push-image WORKERS_ONLY=1 SSH=1 IMAGES="myapp:v1 sidecar:latest"

# or call the script directly
./scripts/push-image.sh --workers-only --ssh myapp:v1
```

## What It Does

1. preflights (`docker` + `incus`/`ssh` available, images exist locally, nodes reachable)
2. `docker save` exports all requested images to a single host-local tar
3. per node, sequentially:
   - transfers the tar (`incus file push` or `scp`)
   - imports into containerd: `ctr -n k8s.io images import <tar>` — the `-n k8s.io` namespace is what kubelet reads
   - removes the remote tar

## Gotchas

- **`imagePullPolicy`** — set `IfNotPresent` (or `Never`) in your pod spec. With `Always`, kubelet ignores the local image and tries to pull from a registry.
- **Image name resolution** — `docker save foo:v1` lands in containerd as `docker.io/library/foo:v1`. Referencing bare `foo:v1` in a pod spec usually resolves, but tagging `localhost/foo:v1` before save is more deterministic.
- **Disk space** — nodes default to 20GiB root disk. The script warns if the tar exceeds 5GiB. Increase `VM_DISK` in `.env` for larger images.
- **Multi-arch images** — `docker save` on a typical dev host emits single-arch, which is what you want. `ctr import` takes the default platform if a multi-arch tar ever shows up.

## When You'd Want a Registry Instead

This command is a one-shot bulk transfer. For tight inner-loop dev (many rebuilds, only a layer or two changes per build), an in-cluster or host-local registry ships less data per iteration. Not implemented here — this is the lightweight path.
