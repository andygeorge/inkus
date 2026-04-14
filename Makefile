.PHONY: up down status prereqs clean

up: prereqs
	@bash scripts/up.sh

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
