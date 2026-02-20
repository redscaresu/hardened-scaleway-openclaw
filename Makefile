MOCKWAY_SRC ?= ../mockway
TF_DIR       = terraform

.PHONY: fmt validate test-plan mockway-build

fmt:
	terraform -chdir=$(TF_DIR) fmt

validate:
	cd $(TF_DIR) && source .env.terraform && terraform validate

mockway-build:
	cd $(MOCKWAY_SRC) && go install ./cmd/mockway

test-plan: mockway-build
	./scripts/test-with-mock.sh
