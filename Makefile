.PHONY: up down status prereqs clean push-image

up: prereqs
	@bash scripts/up.sh

# Transfer local Docker image(s) into containerd on every Inkus node.
#   make push-image IMAGE=myapp:v1
#   make push-image IMAGES="myapp:v1 sidecar:latest"
#   make push-image WORKERS_ONLY=1 IMAGE=myapp:v1
#   make push-image SSH=1 IMAGE=myapp:v1
push-image:
	@if [ -z "$(IMAGE)$(IMAGES)" ]; then \
		echo "usage: make push-image IMAGE=name:tag [WORKERS_ONLY=1] [SSH=1]"; \
		echo "       make push-image IMAGES=\"a:1 b:2\""; \
		exit 1; \
	fi
	@bash scripts/push-image.sh $(if $(filter 1,$(WORKERS_ONLY)),--workers-only) $(if $(filter 1,$(SSH)),--ssh) $(IMAGE) $(IMAGES)

down:
	@bash scripts/down.sh

status:
	@KUBECONFIG=./kubeconfig kubectl get nodes

prereqs:
	@bash scripts/prereqs.sh

clean: down
	rm -rf terraform/.terraform terraform/.terraform.lock.hcl
	rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup
	rm -rf .ssh
	@echo "==> Cleaned all local state."
