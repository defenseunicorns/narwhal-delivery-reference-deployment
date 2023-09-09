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
help: ## Show available user-facing targets
	grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	| sed -n 's/^\(.*\): \(.*\)##\(.*\)/\1:\3/p' \
	| column -t -s ":"

.PHONY: help-extended
help-extended: ## Show available dev-facing targets
	grep -E '^[a-zA-Z0-9_-]+:.*?#_# .*$$' $(MAKEFILE_LIST) \
	| sed -n 's/^\(.*\): \(.*\)#_#\(.*\)/\1:\3/p' \
	| column -t -s ":"

.PHONY: on-prem-lite-up
on-prem-lite-up: ## Full on-prem-lite deployment
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	$(MAKE) -s \
		on-prem-lite-terraform-init \
		on-prem-lite-terraform-apply \
		_sleep180 \
		on-prem-lite-zarf-init \
		on-prem-lite-deploy-metallb \
		on-prem-lite-deploy-dubbd \
		on-prem-lite-deploy-idam \
		on-prem-lite-deploy-sso \
		on-prem-lite-update-server-etc-hosts \
		on-prem-lite-update-local-etc-hosts \
		on-prem-lite-update-coredns-config \
		on-prem-lite-deploy-mission-app

.PHONY: on-prem-lite-down
on-prem-lite-down: ## Teardown on-prem-lite deployment
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	$(MAKE) -s \
		on-prem-lite-rollback-local-etc-hosts \
		on-prem-lite-terraform-destroy

.PHONY: on-prem-lite-terraform-init
on-prem-lite-terraform-init: _create-folders #_# Run terraform init on the on-prem-lite infra
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& terraform init'

.PHONY: on-prem-lite-terraform-plan
on-prem-lite-terraform-plan: _create-folders #_# Run terraform plan on the on-prem-lite infra
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& terraform plan'

.PHONY: on-prem-lite-terraform-apply
on-prem-lite-terraform-apply: _create-folders #_# Run terraform apply on the on-prem-lite infra
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& terraform apply -auto-approve'

.PHONY: on-prem-lite-terraform-destroy
on-prem-lite-terraform-destroy: _create-folders #_# Run terraform destroy on the on-prem-lite infra
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
		&& terraform destroy -auto-approve'

.PHONY: on-prem-lite-start-session
on-prem-lite-start-session: _create-folders #_# Start a session on the on-prem-lite server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id)'

# On Mac there's no good way to install sshpass. Enter the password yourself ya lazy bum. The password is "password".
# Make sure you have the stuff you need installed (sshuttle, ssh, AWS CLI, session manager plugin, etc)
.PHONY: on-prem-lite-start-sshuttle
on-prem-lite-start-sshuttle: _create-folders #_# Start an Sshuttle session with the on-prem-lite server
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	sshuttle -e 'ssh -q -o CheckHostIP=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="aws ssm --region $(shell docker run ${ALL_THE_DOCKER_ARGS} bash -c 'cd deployments/on-prem-lite/terraform && terraform output -raw region') start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"' --dns --disable-ipv6 -vr ec2-user@$(shell docker run ${ALL_THE_DOCKER_ARGS} bash -c 'cd deployments/on-prem-lite/terraform && terraform output -raw server_id') $(shell docker run ${ALL_THE_DOCKER_ARGS} bash -c 'cd deployments/on-prem-lite/terraform && terraform output -raw vpc_cidr') 10.0.255.0/24 \

.PHONY: on-prem-lite-zarf-init
on-prem-lite-zarf-init: _create-folders #_# Run 'zarf init' on the on-prem-lite server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo /usr/local/bin/zarf init \
						--components=k3s,git-server \
						--set K3S_ARGS=\"--disable traefik,servicelb\" \
						--confirm \
				"]'"'"''

.PHONY: on-prem-lite-deploy-metallb
on-prem-lite-deploy-metallb: _create-folders #_# Deploy Metallb
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo /usr/local/bin/zarf package deploy \
						oci://ghcr.io/defenseunicorns/packages/metallb:${METALLB_VERSION}-amd64 \
						--set IP_ADDRESS_POOL=10.0.255.0/24 \
						--confirm \
				"]'"'"''

# TODO: Take out this APPROVED_REGISTRIES thing. See https://github.com/defenseunicorns/uds-sso/issues/25
.PHONY: on-prem-lite-deploy-dubbd
on-prem-lite-deploy-dubbd: _create-folders #_# Deploy DUBBD
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo /usr/local/bin/zarf package deploy \
						oci://ghcr.io/defenseunicorns/packages/dubbd-k3d:${DUBBD_VERSION}-amd64 \
						--set=APPROVED_REGISTRIES=\"127.0.0.1* | ghcr.io/defenseunicorns/pepr* | ghcr.io/stefanprodan* | registry1.dso.mil\" \
						--confirm \
				"]'"'"''

.PHONY: on-prem-lite-deploy-idam
on-prem-lite-deploy-idam: _create-folders #_# Deploy the IDAM package (Keycloak)
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo /usr/local/bin/zarf package deploy \
						oci://ghcr.io/defenseunicorns/uds-capability/uds-idam:${IDAM_VERSION}-amd64 \
						--confirm \
				"]'"'"''

.PHONY: on-prem-lite-deploy-sso
on-prem-lite-deploy-sso: _create-folders #_# Deploy the SSO package (Pepr and Authservice)
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo /usr/local/bin/zarf package deploy \
						oci://ghcr.io/defenseunicorns/uds-capability/uds-sso:${SSO_VERSION}-amd64 \
						--confirm \
				"]'"'"''

.PHONY: on-prem-lite-update-server-etc-hosts
on-prem-lite-update-server-etc-hosts: _create-folders #_# Update the /etc/hosts file on the server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					echo \"$(shell base64 scripts/on-prem-lite/update-server-etc-hosts.sh)\" | sudo tee /root/update-server-etc-hosts.b64 \
					&& sudo base64 -d /root/update-server-etc-hosts.b64 | sudo tee /root/update-server-etc-hosts.sh \
					&& sudo chmod +x /root/update-server-etc-hosts.sh \
					&& sudo /root/update-server-etc-hosts.sh \
				"]'"'"''

.PHONY: on-prem-lite-update-coredns-config
on-prem-lite-update-coredns-config: _create-folders #_# Update the CoreDNS config on the server
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					echo \"$(shell base64 scripts/on-prem-lite/update-coredns.sh)\" | sudo tee /root/update-coredns.b64 \
						&& sudo base64 -d /root/update-coredns.b64 | sudo tee /root/update-coredns.sh \
						&& sudo chmod +x /root/update-coredns.sh \
						&& sudo /root/update-coredns.sh \
				"]'"'"''

.PHONY: on-prem-lite-update-local-etc-hosts
on-prem-lite-update-local-etc-hosts: _create-folders #_# Update the /etc/hosts file on the local machine
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	chmod +x scripts/on-prem-lite/update-local-etc-hosts.sh && scripts/on-prem-lite/update-local-etc-hosts.sh

.PHONY: on-prem-lite-rollback-local-etc-hosts
on-prem-lite-rollback-local-etc-hosts: _create-folders #_# Rollback the /etc/hosts file on the local machine
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
	chmod +x scripts/on-prem-lite/rollback-local-etc-hosts.sh && scripts/on-prem-lite/rollback-local-etc-hosts.sh

.PHONY: on-prem-lite-deploy-mission-app
on-prem-lite-deploy-mission-app: _create-folders #_# Deploy the Mission App
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo /usr/local/bin/zarf package deploy \
						oci://ghcr.io/defenseunicorns/narwhal-delivery-zarf-package-podinfo/podinfo:${MISSION_APP_VERSION}-amd64 \
						--confirm \
						-l debug \
				"]'"'"''

.PHONY: on-prem-lite-destroy-cluster
on-prem-lite-destroy-cluster: _create-folders #_# Destroy the Kubernetes cluster (but not the server)
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo /usr/local/bin/zarf destroy \
						--remove-components \
						--confirm \
				"]'"'"''

.PHONY: _on-prem-lite-get-admin-ingressgateway-ip
_on-prem-lite-get-admin-ingressgateway-ip: _create-folders #_# Get the IP address of the admin-ingressgateway service
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo kubectl get svc admin-ingressgateway -n istio-system -o=jsonpath=\"{.status.loadBalancer.ingress[0].ip}\" \
				"]'"'"' | sed "/session/d" | sed "/^$$/d" | tr -d "\\n"'

.PHONY: _on-prem-lite-get-keycloak-ingressgateway-ip
_on-prem-lite-get-keycloak-ingressgateway-ip: _create-folders #_# Get the IP address of the keycloak-ingressgateway service
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo kubectl get svc keycloak-ingressgateway -n istio-system -o=jsonpath=\"{.status.loadBalancer.ingress[0].ip}\" \
				"]'"'"' | sed "/session/d" | sed "/^$$/d" | tr -d "\\n"'

.PHONY: _on-prem-lite-get-tenant-ingressgateway-ip
_on-prem-lite-get-tenant-ingressgateway-ip: _create-folders #_# Get the IP address of the tenant-ingressgateway service
ifndef AWS_ACCESS_KEY_ID
	$(error AWS CLI environment variables are not set)
endif
	docker run ${ALL_THE_DOCKER_ARGS} \
		bash -c 'cd deployments/on-prem-lite/terraform \
			&& aws ssm start-session \
				--region $$(terraform output -raw region) \
				--target $$(terraform output -raw server_id) \
				--document-name AWS-StartInteractiveCommand \
				--parameters command='"'"'[" \
					sudo kubectl get svc tenant-ingressgateway -n istio-system -o=jsonpath=\"{.status.loadBalancer.ingress[0].ip}\" \
				"]'"'"' | sed "/session/d" | sed "/^$$/d" | tr -d "\\n"'

.PHONY: _sleep180
_sleep180: #_# Sleep for 180 seconds
	echo "Sleeping for 180 seconds to allow the instance user data script to finish"
	sleep 180

.PHONY: _create-folders
_create-folders: #_# Create the .cache folder structure
	mkdir -p .cache/docker
	mkdir -p .cache/pre-commit
	mkdir -p .cache/go
	mkdir -p .cache/go-build
	mkdir -p .cache/tmp
	mkdir -p .cache/.terraform.d/plugin-cache
	mkdir -p .cache/.zarf-cache

.PHONY: docker-save-build-harness
docker-save-build-harness: _create-folders #_# Save the build-harness docker image to the .cache folder
	docker pull ${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION}
	docker save -o .cache/docker/build-harness.tar ${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION}

.PHONY: docker-load-build-harness
docker-load-build-harness: #_# Load the build-harness docker image from the .cache folder
	docker load -i .cache/docker/build-harness.tar

.PHONY: _runhooks
_runhooks: _create-folders #_# [internal] Run pre-commit hooks
	docker run ${ALL_THE_DOCKER_ARGS} \
	bash -c 'git config --global --add safe.directory /app \
		&& pre-commit run -a --show-diff-on-failure $(HOOK)'

.PHONY: pre-commit-all
pre-commit-all: #_# Run all pre-commit hooks
	$(MAKE) _runhooks HOOK="" SKIP=""

.PHONY: pre-commit-terraform
pre-commit-terraform: #_# Run terraform pre-commit hooks
	$(MAKE) _runhooks HOOK="" SKIP="check-added-large-files,check-merge-conflict,detect-aws-credentials,detect-private-key,end-of-file-fixer,fix-byte-order-marker,trailing-whitespace,check-yaml,fix-smartquotes,go-fmt,golangci-lint,renovate-config-validator"

.PHONY: pre-commit-golang
pre-commit-golang: #_# Run golang pre-commit hooks
	$(MAKE) _runhooks HOOK="" SKIP="check-added-large-files,check-merge-conflict,detect-aws-credentials,detect-private-key,end-of-file-fixer,fix-byte-order-marker,trailing-whitespace,check-yaml,fix-smartquotes,terraform_fmt,terraform_docs,terraform_checkov,terraform_tflint,renovate-config-validator"

.PHONY: pre-commit-renovate
pre-commit-renovate: #_# Run renovate pre-commit hooks
	$(MAKE) _runhooks HOOK="renovate-config-validator" SKIP=""

.PHONY: pre-commit-common
pre-commit-common: #_# Run common pre-commit hooks
	$(MAKE) _runhooks HOOK="" SKIP="go-fmt,golangci-lint,terraform_fmt,terraform_docs,terraform_checkov,terraform_tflint,renovate-config-validator"

.PHONY: fix-cache-permissions
fix-cache-permissions: #_# Fix permissions on the .cache folder
	docker run $(TTY_ARG) --rm -v "${PWD}:/app" --workdir "/app" -e "PRE_COMMIT_HOME=/app/.cache/pre-commit" ${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION} chmod -R a+rx .cache

.PHONY: autoformat
autoformat: #_# Autoformat all files
	$(MAKE) _runhooks HOOK="" SKIP="check-added-large-files,check-merge-conflict,detect-aws-credentials,detect-private-key,check-yaml,golangci-lint,terraform_checkov,terraform_tflint,renovate-config-validator"
