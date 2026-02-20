TF_DIR = terraform

.PHONY: fmt validate test-plan test-apply

fmt:
	terraform -chdir=$(TF_DIR) fmt

validate:
	cd $(TF_DIR) && source .env.terraform && terraform validate

test-plan:
	./scripts/test-plan.sh

test-apply:
	@command -v mockway >/dev/null 2>&1 || go install github.com/redscaresu/mockway/cmd/mockway@latest
	./scripts/test-with-mock.sh
