include .env

.DEFAULT_GOAL := help

SHELL := /bin/bash

ZARF := zarf --no-progress --no-log-file

# DRY is good.
ALL_THE_DOCKER_ARGS := $(TTY_ARG) -it --rm \
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
help: ## Show available user-facing targets
	grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	| sed -n 's/^\(.*\): \(.*\)##\(.*\)/\1:\3/p' \
	| column -t -s ":"

.PHONY: help-dev
help-dev: ## Show available dev-facing targets
	grep -E '^_[a-zA-Z0-9_-]+:.*?#_# .*$$' $(MAKEFILE_LIST) \
	| sed -n 's/^\(.*\): \(.*\)#_#\(.*\)/\1:\3/p' \
	| column -t -s ":"

.PHONY: help-internal
help-internal: ## Show available internal targets
	grep -E '^\+[a-zA-Z0-9_-]+:.*?#\+# .*$$' $(MAKEFILE_LIST) \
	| sed -n 's/^\(.*\): \(.*\)#\+#\(.*\)/\1:\3/p' \
	| column -t -s ":"

.PHONY: on-prem-lite-up
on-prem-lite-up: ## [Docker] Full on-prem-lite deployment
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-up'

.PHONY: on-prem-lite-down
on-prem-lite-down: ## [Docker] Destroy the on-prem-lite deployment
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-terraform-destroy'

.PHONY: on-prem-lite-update-local-etc-hosts
on-prem-lite-update-local-etc-hosts: ## [Docker] Update the /etc/hosts file on the local machine
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	chmod +x scripts/on-prem-lite/update-local-etc-hosts.sh && scripts/on-prem-lite/update-local-etc-hosts.sh

# On Mac there's no good way to install sshpass. Enter the password yourself ya lazy bum. The password is "password".
# Make sure you have the stuff you need installed (sshuttle, ssh, AWS CLI, session manager plugin, etc)
.PHONY: on-prem-lite-start-sshuttle
on-prem-lite-start-sshuttle: +create-folders ## Start an Sshuttle connection with the on-prem-lite server
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	sshuttle -e 'ssh -q -o CheckHostIP=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="aws ssm --region $(shell docker run ${ALL_THE_DOCKER_ARGS} bash -c 'cd deployments/on-prem-lite/terraform && terraform output -raw region') start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"' --dns --disable-ipv6 -vr ec2-user@$(shell docker run ${ALL_THE_DOCKER_ARGS} bash -c 'cd deployments/on-prem-lite/terraform && terraform output -raw server_id') $(shell docker run ${ALL_THE_DOCKER_ARGS} bash -c 'cd deployments/on-prem-lite/terraform && terraform output -raw vpc_cidr') 10.0.255.0/24 \


.PHONY: on-prem-lite-rollback-local-etc-hosts
on-prem-lite-rollback-local-etc-hosts: ## Rollback the /etc/hosts file on the local machine
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
	chmod +x scripts/on-prem-lite/rollback-local-etc-hosts.sh && scripts/on-prem-lite/rollback-local-etc-hosts.sh

.PHONY: _test-on-prem-lite
_test-on-prem-lite: #_# [Docker] Stand up the on-prem-lite deployment, run the test, then tear it down
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	FAILURE=0; \
	$(MAKE) on-prem-lite-up || FAILURE=1; \
	[[ $$FAILURE -eq 0 ]] && make +on-prem-lite-go-test || FAILURE=1; \
	make on-prem-lite-down || FAILURE=1; \
	exit $$FAILURE; \

.PHONY: _on-prem-lite-terraform-init
_on-prem-lite-terraform-init: +create-folders #_# [Docker] Run terraform init on the on-prem-lite infra
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-terraform-init'

.PHONY: _on-prem-lite-terraform-plan
_on-prem-lite-terraform-plan: +create-folders #_# [Docker] Run terraform plan on the on-prem-lite infra
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-terraform-plan'

.PHONY: _on-prem-lite-terraform-apply
_on-prem-lite-terraform-apply: +create-folders #_# [Docker] Run terraform apply on the on-prem-lite infra
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-terraform-apply'

.PHONY: _on-prem-lite-terraform-destroy
_on-prem-lite-terraform-destroy: +create-folders #_# [Docker] Run terraform destroy on the on-prem-lite infra
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-terraform-destroy'

.PHONY: _on-prem-lite-start-session
_on-prem-lite-start-session: +create-folders #_# [Docker] Start a session on the on-prem-lite server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id)'

.PHONY: _on-prem-lite-zarf-init
_on-prem-lite-zarf-init: +create-folders #_# [Docker] Run 'zarf init' on the on-prem-lite server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-zarf-init'

.PHONY: _on-prem-lite-deploy-metallb
_on-prem-lite-deploy-metallb: +create-folders #_# [Docker] Deploy Metallb
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-deploy-metallb'

.PHONY: _on-prem-lite-deploy-dubbd
_on-prem-lite-deploy-dubbd: +create-folders #_# [Docker] Deploy DUBBD
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-deploy-dubbd'

.PHONY: _on-prem-lite-deploy-idam
_on-prem-lite-deploy-idam: +create-folders #_# [Docker] Deploy the IDAM package (Keycloak)
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-deploy-idam'

.PHONY: _on-prem-lite-deploy-sso
_on-prem-lite-deploy-sso: +create-folders #_# [Docker] Deploy the SSO package (Pepr and Authservice)
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-deploy-sso'

.PHONY: _on-prem-lite-update-server-etc-hosts
_on-prem-lite-update-server-etc-hosts: +create-folders #_# [Docker] Update the /etc/hosts file on the server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-update-server-etc-hosts'

.PHONY: _on-prem-lite-update-coredns-config
_on-prem-lite-update-coredns-config: +create-folders #_# [Docker] Update the CoreDNS config on the server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-update-coredns-config'

.PHONY: _on-prem-lite-deploy-mission-app
_on-prem-lite-deploy-mission-app: +create-folders #_# [Docker] Deploy the Mission App
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-deploy-mission-app'

.PHONY: _on-prem-lite-destroy-cluster
_on-prem-lite-destroy-cluster: +create-folders #_# [Docker] Destroy the Kubernetes cluster (but not the server)
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-destroy-cluster'

.PHONY: _on-prem-lite-get-admin-ingressgateway-ip
_on-prem-lite-get-admin-ingressgateway-ip: +create-folders #_# [Docker] Get the IP address of the admin-ingressgateway service
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-get-admin-ingressgateway-ip'

.PHONY: _on-prem-lite-get-keycloak-ingressgateway-ip
_on-prem-lite-get-keycloak-ingressgateway-ip: +create-folders #_# [Docker] Get the IP address of the keycloak-ingressgateway service
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-get-keycloak-ingressgateway-ip'

.PHONY: _on-prem-lite-get-tenant-ingressgateway-ip
_on-prem-lite-get-tenant-ingressgateway-ip: +create-folders #_# [Docker] Get the IP address of the tenant-ingressgateway service
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-get-tenant-ingressgateway-ip'

.PHONY: _docker-save-build-harness
_docker-save-build-harness: +create-folders #_# Save the build-harness docker image to the .cache folder
	docker pull ${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION}
	docker save -o .cache/docker/build-harness.tar ${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION}

.PHONY: _docker-load-build-harness
_docker-load-build-harness: #_# Load the build-harness docker image from the .cache folder
	docker load -i .cache/docker/build-harness.tar

.PHONY: _pre-commit-all
_pre-commit-all: #_# [Docker] Run all pre-commit hooks
	$(MAKE) +runhooks HOOK="" SKIP=""

.PHONY: +pre-commit-terraform
_pre-commit-terraform: #_# [Docker] Run terraform pre-commit hooks
	$(MAKE) +runhooks HOOK="" SKIP="check-added-large-files,check-merge-conflict,detect-aws-credentials,detect-private-key,end-of-file-fixer,fix-byte-order-marker,trailing-whitespace,check-yaml,fix-smartquotes,go-fmt,golangci-lint,renovate-config-validator"

.PHONY: _pre-commit-golang
_pre-commit-golang: #_# [Docker] Run golang pre-commit hooks
	$(MAKE) +runhooks HOOK="" SKIP="check-added-large-files,check-merge-conflict,detect-aws-credentials,detect-private-key,end-of-file-fixer,fix-byte-order-marker,trailing-whitespace,check-yaml,fix-smartquotes,terraform_fmt,terraform_docs,terraform_checkov,terraform_tflint,renovate-config-validator"

.PHONY: _pre-commit-renovate
_pre-commit-renovate: #_# [Docker] Run renovate pre-commit hooks
	$(MAKE) +runhooks HOOK="renovate-config-validator" SKIP=""

.PHONY: _pre-commit-common
_pre-commit-common: #_# [Docker] Run common pre-commit hooks
	$(MAKE) +runhooks HOOK="" SKIP="go-fmt,golangci-lint,terraform_fmt,terraform_docs,terraform_checkov,terraform_tflint,renovate-config-validator"

.PHONY: _fix-cache-permissions
_fix-cache-permissions: #_# [Docker] Fix permissions on the .cache folder
	docker run $(TTY_ARG) --rm -v "${PWD}:/app" --workdir "/app" -e "PRE_COMMIT_HOME=/app/.cache/pre-commit" ${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION} chmod -R a+rx .cache

.PHONY: _autoformat
_autoformat: #_# [Docker] Autoformat all files
	$(MAKE) +runhooks HOOK="" SKIP="check-added-large-files,check-merge-conflict,detect-aws-credentials,detect-private-key,check-yaml,golangci-lint,terraform_checkov,terraform_tflint,renovate-config-validator"

.PHONY: +on-prem-lite-go-test
+on-prem-lite-go-test: #+# [Docker] Run the E2E test for the on-prem-lite deployment
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	echo "Starting test run. You may not see any output for a bit."
	docker run -v /var/run/docker.sock:/var/run/docker.sock ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-start-sshuttle-in-background \
			&& make +on-prem-lite-update-local-etc-hosts \
			&& cd test/e2e \
			&& sleep 10 \
			&& go test -count 1 -v -timeout 2h -run TestOnPremLite'

.PHONY: +on-prem-lite-up
+on-prem-lite-up: #+# Full on-prem-lite deployment
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	$(MAKE) -s \
		+on-prem-lite-terraform-init \
		+on-prem-lite-terraform-apply \
		+on-prem-lite-wait-for-zarf-no-docker \
		+on-prem-lite-zarf-init \
		+on-prem-lite-deploy-metallb \
		+on-prem-lite-deploy-dubbd \
		+on-prem-lite-deploy-idam \
		+on-prem-lite-deploy-sso \
		+on-prem-lite-update-server-etc-hosts \
		+on-prem-lite-update-coredns-config \
		+on-prem-lite-deploy-mission-app

.PHONY: +on-prem-lite-terraform-init
+on-prem-lite-terraform-init: #+# Run terraform init on the on-prem-lite infra
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& terraform init

.PHONY: +on-prem-lite-terraform-plan
+on-prem-lite-terraform-plan: +create-folders #_# Run terraform plan on the on-prem-lite infra
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& terraform plan

.PHONY: +on-prem-lite-terraform-apply
+on-prem-lite-terraform-apply: +create-folders #+# Run terraform apply on the on-prem-lite infra
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& terraform apply -auto-approve

.PHONY: +on-prem-lite-zarf-init
+on-prem-lite-zarf-init: +create-folders #+# Run 'zarf init' on the on-prem-lite server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& aws ssm start-session \
			--region $$(terraform output -raw region) \
			--target $$(terraform output -raw server_id) \
			--document-name AWS-StartInteractiveCommand \
			--parameters command='[" \
				sudo $(ZARF) init \
					--components=k3s,git-server \
					--set K3S_ARGS=\"--disable traefik,servicelb\" \
					--confirm \
				&& echo \"EXITCODE: 0\" \
			"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: +on-prem-lite-deploy-metallb
+on-prem-lite-deploy-metallb: +create-folders #+# Deploy Metallb
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& aws ssm start-session \
			--region $$(terraform output -raw region) \
			--target $$(terraform output -raw server_id) \
			--document-name AWS-StartInteractiveCommand \
			--parameters command='[" \
				sudo $(ZARF) package deploy \
					oci://ghcr.io/defenseunicorns/packages/metallb:${METALLB_VERSION}-amd64 \
					--set IP_ADDRESS_POOL=10.0.255.0/24 \
					--confirm \
				&& echo \"EXITCODE: 0\" \
			"]' | tee /dev/tty | grep -q "EXITCODE: 0"

# TODO: Take out this APPROVED_REGISTRIES thing. See https://github.com/defenseunicorns/uds-sso/issues/25
.PHONY: +on-prem-lite-deploy-dubbd
+on-prem-lite-deploy-dubbd: +create-folders #+# Deploy DUBBD
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& aws ssm start-session \
			--region $$(terraform output -raw region) \
			--target $$(terraform output -raw server_id) \
			--document-name AWS-StartInteractiveCommand \
			--parameters command='[" \
				sudo $(ZARF) package deploy \
					oci://ghcr.io/defenseunicorns/packages/dubbd-k3d:${DUBBD_VERSION}-amd64 \
					--set=APPROVED_REGISTRIES=\"127.0.0.1* | ghcr.io/defenseunicorns/pepr* | ghcr.io/stefanprodan* | registry1.dso.mil\" \
					--confirm \
				&& echo \"EXITCODE: 0\" \
			"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: +on-prem-lite-deploy-idam
+on-prem-lite-deploy-idam: +create-folders #+# Deploy the IDAM package (Keycloak)
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& aws ssm start-session \
			--region $$(terraform output -raw region) \
			--target $$(terraform output -raw server_id) \
			--document-name AWS-StartInteractiveCommand \
			--parameters command='[" \
				sudo $(ZARF) package deploy \
					oci://ghcr.io/defenseunicorns/uds-capability/uds-idam:${IDAM_VERSION}-amd64 \
					--set=KEYCLOAK_DEV_DB_ENABLED=true \
					--confirm \
				&& echo \"EXITCODE: 0\" \
			"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: +on-prem-lite-deploy-sso
+on-prem-lite-deploy-sso: +create-folders #+# Deploy the SSO package (Pepr and Authservice)
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& aws ssm start-session \
			--region $$(terraform output -raw region) \
			--target $$(terraform output -raw server_id) \
			--document-name AWS-StartInteractiveCommand \
			--parameters command='[" \
				sudo $(ZARF) package deploy \
					oci://ghcr.io/defenseunicorns/uds-capability/uds-sso:${SSO_VERSION}-amd64 \
					--confirm \
				&& echo \"EXITCODE: 0\" \
			"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: +on-prem-lite-update-server-etc-hosts
+on-prem-lite-update-server-etc-hosts: +create-folders #+# Update the /etc/hosts file on the server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	aws ssm start-session \
		--region $(shell cd deployments/on-prem-lite/terraform && terraform output -raw region) \
		--target $(shell cd deployments/on-prem-lite/terraform && terraform output -raw server_id) \
		--document-name AWS-StartInteractiveCommand \
		--parameters command='[" \
			echo \"$(shell base64 scripts/on-prem-lite/update-server-etc-hosts.sh | tr -d "\n")\" | sudo tee /root/update-server-etc-hosts.b64 \
			&& sudo base64 -d /root/update-server-etc-hosts.b64 | sudo tee /root/update-server-etc-hosts.sh \
			&& sudo chmod +x /root/update-server-etc-hosts.sh \
			&& sudo /root/update-server-etc-hosts.sh \
			&& echo \"EXITCODE: 0\" \
		"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: +on-prem-lite-update-coredns-config
+on-prem-lite-update-coredns-config: +create-folders #+# Update the CoreDNS config on the server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& aws ssm start-session \
			--region $$(terraform output -raw region) \
			--target $$(terraform output -raw server_id) \
			--document-name AWS-StartInteractiveCommand \
			--parameters command='[" \
				echo \"$(shell base64 scripts/on-prem-lite/update-coredns.sh | tr -d "\n")\" | sudo tee /root/update-coredns.b64 \
					&& sudo base64 -d /root/update-coredns.b64 | sudo tee /root/update-coredns.sh \
					&& sudo chmod +x /root/update-coredns.sh \
					&& sudo /root/update-coredns.sh \
					&& echo \"EXITCODE: 0\" \
			"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: +on-prem-lite-update-local-etc-hosts
+on-prem-lite-update-local-etc-hosts: #+# Update the /etc/hosts file on the local machine. Doesn't use Docker.
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	chmod +x scripts/on-prem-lite/update-local-etc-hosts-no-docker.sh && scripts/on-prem-lite/update-local-etc-hosts-no-docker.sh

.PHONY: +on-prem-lite-deploy-mission-app
+on-prem-lite-deploy-mission-app: +create-folders #+# Deploy the Mission App
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& aws ssm start-session \
			--region $$(terraform output -raw region) \
			--target $$(terraform output -raw server_id) \
			--document-name AWS-StartInteractiveCommand \
			--parameters command='[" \
				sudo $(ZARF) package deploy \
					oci://ghcr.io/defenseunicorns/narwhal-delivery-zarf-package-podinfo/podinfo:${MISSION_APP_VERSION}-amd64 \
					--confirm \
					-l debug \
				&& echo \"EXITCODE: 0\" \
			"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: +on-prem-lite-destroy-cluster
+on-prem-lite-destroy-cluster: +create-folders #+# Destroy the Kubernetes cluster (but not the server)
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& aws ssm start-session \
			--region $$(terraform output -raw region) \
			--target $$(terraform output -raw server_id) \
			--document-name AWS-StartInteractiveCommand \
			--parameters command='[" \
				sudo $(ZARF) destroy \
					--remove-components \
					--confirm \
				&& echo \"EXITCODE: 0\" \
			"]' | tee /dev/tty | grep -q "EXITCODE: 0"

# Potentially running terraform destroy twice because of https://github.com/defenseunicorns/terraform-aws-uds-bastion/issues/47
.PHONY: +on-prem-lite-terraform-destroy
+on-prem-lite-terraform-destroy: #+# Run terraform destroy on the on-prem-lite infra
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& terraform destroy -auto-approve || terraform destroy -auto-approve

.PHONY: +on-prem-lite-start-sshuttle-in-background
+on-prem-lite-start-sshuttle-in-background: #+# Start Sshuttle in the background.
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	sshuttle -D -e 'sshpass -p "password" ssh -q -o CheckHostIP=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="aws ssm --region $(shell cd deployments/on-prem-lite/terraform && terraform output -raw region) start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"' --dns --disable-ipv6 -vr ec2-user@$(shell cd deployments/on-prem-lite/terraform && terraform output -raw server_id) $(shell cd deployments/on-prem-lite/terraform && terraform output -raw vpc_cidr) 10.0.255.0/24

.PHONY: +on-prem-lite-get-admin-ingressgateway-ip
+on-prem-lite-get-admin-ingressgateway-ip: #_# Get the IP address of the admin-ingressgateway service
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& aws ssm start-session \
			--region $$(terraform output -raw region) \
			--target $$(terraform output -raw server_id) \
			--document-name AWS-StartInteractiveCommand \
			--parameters command='[" \
				sudo kubectl get svc admin-ingressgateway -n istio-system -o=jsonpath=\"{.status.loadBalancer.ingress[0].ip}\" \
			"]' | sed "/session/d" | sed "/^$$/d" | tr -d "\\n"

.PHONY: +on-prem-lite-get-keycloak-ingressgateway-ip
+on-prem-lite-get-keycloak-ingressgateway-ip: #+# Get the IP address of the keycloak-ingressgateway service
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& aws ssm start-session \
			--region $$(terraform output -raw region) \
			--target $$(terraform output -raw server_id) \
			--document-name AWS-StartInteractiveCommand \
			--parameters command='[" \
				sudo kubectl get svc keycloak-ingressgateway -n istio-system -o=jsonpath=\"{.status.loadBalancer.ingress[0].ip}\" \
			"]' | sed "/session/d" | sed "/^$$/d" | tr -d "\\n"

.PHONY: +on-prem-lite-get-tenant-ingressgateway-ip
+on-prem-lite-get-tenant-ingressgateway-ip: #_# Get the IP address of the tenant-ingressgateway service
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	cd deployments/on-prem-lite/terraform \
		&& aws ssm start-session \
			--region $$(terraform output -raw region) \
			--target $$(terraform output -raw server_id) \
			--document-name AWS-StartInteractiveCommand \
			--parameters command='[" \
				sudo kubectl get svc tenant-ingressgateway -n istio-system -o=jsonpath=\"{.status.loadBalancer.ingress[0].ip}\" \
			"]' | sed "/session/d" | sed "/^$$/d" | tr -d "\\n"

.PHONY: +create-folders
+create-folders: #+# Create the .cache folder structure
	mkdir -p .cache/docker
	mkdir -p .cache/pre-commit
	mkdir -p .cache/go
	mkdir -p .cache/go-build
	mkdir -p .cache/tmp
	mkdir -p .cache/.terraform.d/plugin-cache
	mkdir -p .cache/.zarf-cache

.PHONY: +on-prem-lite-wait-for-zarf
+on-prem-lite-wait-for-zarf: #+# [Docker] Wait for Zarf to be installed in the on-prem-lite server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'make +on-prem-lite-wait-for-zarf-no-docker'

.PHONY: +on-prem-lite-wait-for-zarf-no-docker
+on-prem-lite-wait-for-zarf-no-docker: #+# Wait for Zarf to be installed in the on-prem-lite server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	START_TIME=$$(date +%s); \
	while true; do \
		if aws ssm start-session \
				--region $(shell cd deployments/on-prem-lite/terraform && terraform output -raw region) \
				--target $(shell cd deployments/on-prem-lite/terraform && terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='["whoami"]'; then \
			break; \
		fi; \
		CURRENT_TIME=$$(date +%s); \
		ELAPSED_TIME=$$((CURRENT_TIME - START_TIME)); \
		if [[ $$ELAPSED_TIME -ge 300 ]]; then \
			echo "Timed out waiting for instance to be available"; \
			exit 1; \
		fi; \
		echo "Instance is not available yet. Retrying in 10 seconds"; \
		sleep 10; \
	done; \
	aws ssm start-session \
		--region $(shell cd deployments/on-prem-lite/terraform && terraform output -raw region) \
		--target $(shell cd deployments/on-prem-lite/terraform && terraform output -raw server_id) \
		--document-name AWS-StartInteractiveCommand \
		--parameters command='[" \
			START_TIME=$$(date +%s); \
			while true; do \
				if $(ZARF) version; then \
					echo \"EXITCODE: 0\"; \
					exit 0; \
				fi; \
				CURRENT_TIME=$$(date +%s); \
				ELAPSED_TIME=$$((CURRENT_TIME - START_TIME)); \
				if [[ $$ELAPSED_TIME -ge 300 ]]; then \
					echo \"Timed out waiting for Zarf to be installed\"; \
					echo \"EXITCODE: 1\"; \
					exit 1; \
				fi; \
				echo \" Zarf is not installed yet. Retrying in 10 seconds\"; \
				sleep 10; \
			done; \
		"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: +scriptwrap
+scriptwrap: #+# Wrap a target in the `script` command to simulate a TTY
	script -q -e -c '$(MAKE) $(TARGET)' /dev/null

.PHONY: +runhooks
+runhooks: +create-folders #+# Helper "function" for running pre-commits
	docker run ${ALL_THE_DOCKER_ARGS} \
	bash -c 'git config --global --add safe.directory /app \
		&& pre-commit run -a --show-diff-on-failure $(HOOK)'