include .env

.DEFAULT_GOAL := help

# Optionally add the "-it" flag for docker run commands if the env var "CI" is not set (meaning we are on a local machine and not in github actions)
TTY_ARG :=
ifndef CI
	TTY_ARG := -it
endif

# DRY is good.
ALL_THE_DOCKER_ARGS := $(TTY_ARG) --rm \
	--cap-add=NET_ADMIN \
	--cap-add=NET_RAW \
	-v "${PWD}:/app" \
	-v "${PWD}/.cache/tmp:/tmp" \
	-v "${PWD}/.cache/go:/root/go" \
	-v "${PWD}/.cache/go-build:/root/.cache/go-build" \
	-v "${PWD}/.cache/.terraform.d/plugin-cache:/root/.terraform.d/plugin-cache" \
	-v "${PWD}/.cache/.zarf-cache:/root/.zarf-cache" \
	--workdir "/app" \
	-e TF_LOG_PATH \
	-e TF_LOG \
	-e GOPATH=/root/go \
	-e GOCACHE=/root/.cache/go-build \
	-e TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true \
	-e TF_PLUGIN_CACHE_DIR=/root/.terraform.d/plugin-cache \
	-e AWS_REGION \
	-e AWS_DEFAULT_REGION \
	-e AWS_ACCESS_KEY_ID \
	-e AWS_SECRET_ACCESS_KEY \
	-e AWS_SESSION_TOKEN \
	-e AWS_SECURITY_TOKEN \
	-e AWS_SESSION_EXPIRATION \
	${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION}

# Silent mode by default. Run `make VERBOSE=1` to turn off silent mode.
ifndef VERBOSE
.SILENT:
endif

# Idiomatic way to force a target to always run, by having it depend on this dummy target
FORCE:

.PHONY: help
help: ## Show a list of all targets
	grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	| sed -n 's/^\(.*\): \(.*\)##\(.*\)/\1:\3/p' \
	| column -t -s ":"

.PHONY: _create-folders
_create-folders:
	mkdir -p .cache/docker
	mkdir -p .cache/pre-commit
	mkdir -p .cache/go
	mkdir -p .cache/go-build
	mkdir -p .cache/tmp
	mkdir -p .cache/.terraform.d/plugin-cache
	mkdir -p .cache/.zarf-cache

.PHONY: docker-save-build-harness
docker-save-build-harness: _create-folders ## Pulls the build harness docker image and saves it to a tarball
	docker pull ${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION}
	docker save -o .cache/docker/build-harness.tar ${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION}

.PHONY: docker-load-build-harness
docker-load-build-harness: ## Loads the saved build harness docker image
	docker load -i .cache/docker/build-harness.tar

.PHONY: _runhooks
_runhooks: _create-folders
	docker run ${ALL_THE_DOCKER_ARGS} \
	bash -c 'git config --global --add safe.directory /app \
		&& pre-commit run -a --show-diff-on-failure $(HOOK)'

.PHONY: pre-commit-all
pre-commit-all: ## Run all pre-commit hooks. Returns nonzero exit code if any hooks fail. Uses Docker for maximum compatibility
	$(MAKE) _runhooks HOOK="" SKIP=""

.PHONY: pre-commit-terraform
pre-commit-terraform: ## Run the terraform pre-commit hooks. Returns nonzero exit code if any hooks fail. Uses Docker for maximum compatibility
	$(MAKE) _runhooks HOOK="" SKIP="check-added-large-files,check-merge-conflict,detect-aws-credentials,detect-private-key,end-of-file-fixer,fix-byte-order-marker,trailing-whitespace,check-yaml,fix-smartquotes,go-fmt,golangci-lint,renovate-config-validator"

.PHONY: pre-commit-golang
pre-commit-golang: ## Run the golang pre-commit hooks. Returns nonzero exit code if any hooks fail. Uses Docker for maximum compatibility
	$(MAKE) _runhooks HOOK="" SKIP="check-added-large-files,check-merge-conflict,detect-aws-credentials,detect-private-key,end-of-file-fixer,fix-byte-order-marker,trailing-whitespace,check-yaml,fix-smartquotes,terraform_fmt,terraform_docs,terraform_checkov,terraform_tflint,renovate-config-validator"

.PHONY: pre-commit-renovate
pre-commit-renovate: ## Run the renovate pre-commit hooks. Returns nonzero exit code if any hooks fail. Uses Docker for maximum compatibility
	$(MAKE) _runhooks HOOK="renovate-config-validator" SKIP=""

.PHONY: pre-commit-common
pre-commit-common: ## Run the common pre-commit hooks. Returns nonzero exit code if any hooks fail. Uses Docker for maximum compatibility
	$(MAKE) _runhooks HOOK="" SKIP="go-fmt,golangci-lint,terraform_fmt,terraform_docs,terraform_checkov,terraform_tflint,renovate-config-validator"

.PHONY: fix-cache-permissions
fix-cache-permissions: ## Fixes the permissions on the pre-commit cache
	docker run $(TTY_ARG) --rm -v "${PWD}:/app" --workdir "/app" -e "PRE_COMMIT_HOME=/app/.cache/pre-commit" ${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION} chmod -R a+rx .cache

.PHONY: autoformat
autoformat: ## Update files with automatic formatting tools. Uses Docker for maximum compatibility.
	$(MAKE) _runhooks HOOK="" SKIP="check-added-large-files,check-merge-conflict,detect-aws-credentials,detect-private-key,check-yaml,golangci-lint,terraform_checkov,terraform_tflint,renovate-config-validator"

.PHONY: on-prem-lite-terraform-init
on-prem-lite-terraform-init: _create-folders ## Run terraform init on the on-prem-lite infra
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& terraform init'

.PHONY: on-prem-lite-terraform-plan
on-prem-lite-terraform-plan: _create-folders ## Run terraform plan on the on-prem-lite infra
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& terraform plan'

.PHONY: on-prem-lite-terraform-apply
on-prem-lite-terraform-apply: _create-folders ## Run terraform apply on the on-prem-lite infra
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& terraform apply -auto-approve'

.PHONY: on-prem-lite-terraform-destroy
on-prem-lite-terraform-destroy: _create-folders ## Run terraform destroy on the on-prem-lite infra
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
		&& terraform destroy -auto-approve'

.PHONY: on-prem-lite-start-session
on-prem-lite-start-session: _create-folders ## Start a session with the on-prem-lite server
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $(shell cd deployments/on-prem-lite/terraform && terraform output -raw region) \
				--target $(shell cd deployments/on-prem-lite/terraform && terraform output -raw server_id)'

.PHONY: on-prem-lite-zarf-init
on-prem-lite-zarf-init: _create-folders ## Run 'zarf init' on the on-prem-lite server
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $(shell cd deployments/on-prem-lite/terraform && terraform output -raw region) \
				--target $(shell cd deployments/on-prem-lite/terraform && terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo /usr/local/bin/zarf init \
						--components=k3s,git-server \
						--set K3S_ARGS=\"--disable traefik,servicelb\" \
						--confirm \
				"]'"'"''

.PHONY: on-prem-lite-deploy-metallb
on-prem-lite-deploy-metallb: _create-folders ## Deploy Metallb
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $(shell cd deployments/on-prem-lite/terraform && terraform output -raw region) \
				--target $(shell cd deployments/on-prem-lite/terraform && terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo /usr/local/bin/zarf package deploy \
						oci://ghcr.io/defenseunicorns/packages/metallb:${METALLB_VERSION}-amd64 \
						--set IP_ADDRESS_POOL=10.0.255.0/24 \
						--confirm \
				"]'"'"''

.PHONY: on-prem-lite-deploy-dubbd
on-prem-lite-deploy-dubbd: _create-folders ## Deploy DUBBD
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $(shell cd deployments/on-prem-lite/terraform && terraform output -raw region) \
				--target $(shell cd deployments/on-prem-lite/terraform && terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo /usr/local/bin/zarf package deploy \
						oci://ghcr.io/defenseunicorns/packages/dubbd-k3d:${DUBBD_VERSION}-amd64 \
						--confirm \
				"]'"'"''

.PHONY: on-prem-lite-destroy-cluster
on-prem-lite-destroy-cluster: _create-folders ## Destroy the Kubernetes cluster (but not the server)
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $(shell cd deployments/on-prem-lite/terraform && terraform output -raw region) \
				--target $(shell cd deployments/on-prem-lite/terraform && terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo /usr/local/bin/zarf destroy \
						--remove-components \
						--confirm \
				"]'"'"''
