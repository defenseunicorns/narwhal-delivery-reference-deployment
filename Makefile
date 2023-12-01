include .env

.DEFAULT_GOAL := help

SHELL := /bin/bash

ZARF := zarf -l debug --no-progress --no-log-file

# The current branch name
BRANCH := $(shell git symbolic-ref --short HEAD)
# The "primary" directory
PRIMARY_DIR := $(shell pwd)

# Silent mode by default. Run `make <the-target> VERBOSE=1` to turn off silent mode.
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

.PHONY: zarf-init
zarf-init: ## Run 'zarf init' on the local machine. Will create a K3s cluster since the "k3s" component is selected.
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
	$(ZARF) init \
		--components=k3s,git-server \
		--set K3S_ARGS="--disable traefik,servicelb" \
		--confirm

.PHONY: platform-up
platform-up: ## Deploy the secure platform (MetalLB, DUBBD, IDAM, SSO)
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
	make _deploy-metallb \
		_deploy-dubbd \
		_deploy-idam \
		_deploy-sso \
		_update-coredns

.PHONY: mission-app-up
mission-app-up: ## Deploy the mission app
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
	echo "Deploying mission app..."; \
	[ -f "zarf-package-podinfo-amd64-${MISSION_APP_VERSION}.tar.zst" ] > /dev/null || $(ZARF) package pull oci://ghcr.io/defenseunicorns/narwhal-delivery-zarf-package-podinfo/podinfo:${MISSION_APP_VERSION}-amd64; \
 	$(ZARF) package deploy \
		zarf-package-podinfo-amd64-${MISSION_APP_VERSION}.tar.zst \
		--confirm

.PHONY: _test-infra-up
_test-infra-up: #_# Use Terraform to bring up the test server and prepare it for use
	cd test/iac && terraform init && terraform apply --auto-approve
	$(MAKE) _test-wait-for-zarf _test-install-dod-ca _test-clone

# Runs destroy again if the first one fails to complete.
.PHONY: _test-infra-down
_test-infra-down: #_# Use Terraform to bring down the test server
	cd test/iac && terraform init && terraform destroy --auto-approve || terraform destroy -auto-approve

.PHONY: _test-start-session
_test-start-session: #_# Open an interactive shell on the test server
	aws ssm start-session \
		--region $$(cd test/iac && terraform output -raw region) \
		--target $$(cd test/iac && terraform output -raw server_id)

.PHONY: _test-platform-up
_test-platform-up: #_# On the test server, set up the k8s cluster and UDS platform
	REGION=$$(cd test/iac && terraform output -raw region); \
	SERVER_ID=$$(cd test/iac && terraform output -raw server_id); \
	aws ssm start-session \
		--region $$REGION \
		--target $$SERVER_ID \
		--document-name AWS-StartInteractiveCommand \
		--parameters command='[" \
			cd ~/narwhal-delivery-reference-deployment \
			&& git pull \
			&& cp tls.example.cert tls.cert \
			&& cp tls.example.key tls.key \
			&& cp zarf-config.example.yaml zarf-config.yaml \
			&& sudo make zarf-init platform-up \
			&& echo \"EXITCODE: 0\" \
		"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: _test-platform-down
_test-platform-down: #_# On the test server, tear down the UDS platform and k8s cluster
	REGION=$$(cd test/iac && terraform output -raw region); \
	SERVER_ID=$$(cd test/iac && terraform output -raw server_id); \
	aws ssm start-session \
		--region $$REGION \
		--target $$SERVER_ID \
		--document-name AWS-StartInteractiveCommand \
		--parameters command='[" \
			sudo zarf destroy --confirm --remove-components \
			&& echo \"EXITCODE: 0\" \
		"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: _test-mission-app-up
_test-mission-app-up: #_# On the test server, build and deploy the mission app
	REGION=$$(cd test/iac && terraform output -raw region); \
	SERVER_ID=$$(cd test/iac && terraform output -raw server_id); \
	aws ssm start-session \
		--region $$REGION \
		--target $$SERVER_ID \
		--document-name AWS-StartInteractiveCommand \
		--parameters command='[" \
			cd ~/narwhal-delivery-reference-deployment \
			&& git pull \
			&& sudo make mission-app-up \
			&& echo \"EXITCODE: 0\" \
		"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: _test-mission-app-test
_test-mission-app-test: #_# On the test server, run the mission app tests
	REGION=$$(cd test/iac && terraform output -raw region); \
	SERVER_ID=$$(cd test/iac && terraform output -raw server_id); \
	aws ssm start-session \
		--region $$REGION \
		--target $$SERVER_ID \
		--document-name AWS-StartInteractiveCommand \
		--parameters command='[" \
			cd ~/narwhal-delivery-reference-deployment/test \
			&& git pull \
			&& chmod +x ./test-mission.app.sh \
			&& ./test-mission-app.sh \
			&& echo \"EXITCODE: 0\" \
		"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: _test-mission-app-down
_test-mission-app-down: #_# On the test server, tear down the mission app
	error "not implemented yet"

.PHONY: _test-wait-for-zarf
_test-wait-for-zarf: #_# Wait for Zarf to be installed in the test server
	START_TIME=$$(date +%s); \
	REGION=$$(cd test/iac && terraform output -raw region); \
	SERVER_ID=$$(cd test/iac && terraform output -raw server_id); \
	while true; do \
		if aws ssm start-session \
				--region $$REGION \
				--target $$SERVER_ID \
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
		--region $$REGION \
		--target $$SERVER_ID \
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

.PHONY: _test-install-dod-ca
_test-install-dod-ca: #_# Install the DOD CA in the test server
	REGION=$$(cd test/iac && terraform output -raw region); \
	SERVER_ID=$$(cd test/iac && terraform output -raw server_id); \
	aws ssm start-session \
		--region $$REGION \
		--target $$SERVER_ID \
		--document-name AWS-StartInteractiveCommand \
		--parameters command='[" \
			sudo yum install -y -q git \
			&& cd ~ \
			&& wget https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip \
			&& unzip -o unclass-certificates_pkcs7_DoD.zip \
			&& cd certificates_pkcs7_*_dod/ \
			&& sudo cp -f ./dod_pke_chain.pem /etc/pki/ca-trust/source/anchors/ \
			&& sudo update-ca-trust \
			&& echo \"EXITCODE: 0\" \
		"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: _test-clone
_test-clone: #_# Clone the repo in the test instance so we can use it
	aws ssm start-session \
		--region $$(cd test/iac && terraform output -raw region) \
		--target $$(cd test/iac && terraform output -raw server_id) \
		--document-name AWS-StartInteractiveCommand \
		--parameters command='[" \
			rm -rf ~/narwhal-delivery-reference-deployment \
			&& git clone -b $(BRANCH) $(REPO) ~/narwhal-delivery-reference-deployment \
			&& echo \"EXITCODE: 0\" \
		"]' | tee /dev/tty | grep -q "EXITCODE: 0"

.PHONY: _deploy-metallb
_deploy-metallb: _prereqs #_# Deploy the metallb load balancer on the local machine.
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
	echo "Deploying MetalLB..."; \
 	[ -f "zarf-package-metallb-amd64-${METALLB_VERSION}.tar.zst" ] > /dev/null || $(ZARF) package pull oci://ghcr.io/defenseunicorns/packages/metallb:${METALLB_VERSION}-amd64; \
 	$(ZARF) package deploy \
		zarf-package-metallb-amd64-${METALLB_VERSION}.tar.zst \
		--confirm

.PHONY: _deploy-dubbd
_deploy-dubbd: _prereqs #_# Deploy the dubbd package
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
	echo "Deploying DUBBD..."; \
	[ -f "zarf-package-dubbd-k3d-amd64-${DUBBD_VERSION}.tar.zst" ] > /dev/null || $(ZARF) package pull oci://ghcr.io/defenseunicorns/packages/dubbd-k3d:${DUBBD_VERSION}-amd64; \
 	$(ZARF) package deploy \
		zarf-package-dubbd-k3d-amd64-${DUBBD_VERSION}.tar.zst \
		--confirm

.PHONY: _deploy-idam
_deploy-idam: _prereqs #_# Deploy the idam package
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
	echo "Deploying the IDAM package..."; \
 	[ -f "zarf-package-uds-idam-amd64-${IDAM_VERSION}.tar.zst" ] > /dev/null || $(ZARF) package pull oci://ghcr.io/defenseunicorns/uds-capability/uds-idam:${IDAM_VERSION}-amd64; \
 	$(ZARF) package deploy \
		zarf-package-uds-idam-amd64-${IDAM_VERSION}.tar.zst \
		--confirm \

.PHONY: _deploy-sso
_deploy-sso: _prereqs #_# Deploy the sso package
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
	echo "Deploying the SSO package..."; \
	[ -f "zarf-package-uds-sso-amd64-${SSO_VERSION}.tar.zst" ] > /dev/null || $(ZARF) package pull oci://ghcr.io/defenseunicorns/uds-capability/uds-sso:${SSO_VERSION}-amd64; \
 	$(ZARF) package deploy \
		zarf-package-uds-sso-amd64-${SSO_VERSION}.tar.zst \
		--confirm \

# This is ugly as hell, but what it basically does is append the IP address of the keycloak ingress gateway to the coredns configmap so that things inside the cluster can resolve the keycloak domain name.
.PHONY: _update-coredns
_update-coredns: _prereqs #_# Update the coredns configmap to include the keycloak ingress gateway IP. Only needed if you are using the *.bigbang.dev domain
ifneq ($(shell id -u), 0)
	$(error "This target must be run as root")
endif
	zarf tools kubectl get cm coredns -n kube-system -o jsonpath='{.data.NodeHosts}' | grep -q "$(shell zarf tools kubectl get svc keycloak-ingressgateway -n istio-system -o=jsonpath='{.status.loadBalancer.ingress[0].ip}') keycloak" || zarf tools kubectl patch cm coredns -n kube-system --type='json' -p="[{\"op\": \"replace\", \"path\": \"/data/NodeHosts\", \"value\":\"$(shell zarf tools kubectl get cm coredns -n kube-system -o jsonpath='{.data.NodeHosts}')\n$(shell zarf tools kubectl get svc keycloak-ingressgateway -n istio-system -o=jsonpath='{.status.loadBalancer.ingress[0].ip}') keycloak.bigbang.dev\"}]"
	zarf tools kubectl rollout restart deployment coredns -n kube-system

.PHONY: _prereqs
_prereqs: #_# Run prerequisite checks
	zarf tools kubectl get nodes > /dev/null || (echo "ERROR: unable to establish clean connection to the kubernetes cluster. If you don't have one yet and want one on the local (Linux) machine you can run 'sudo zarf init --components=k3s,git-server --set K3S_ARGS=\"--disable traefik,servicelb\" --confirm'" && exit 1)
	zarf tools kubectl -n zarf get sts zarf-gitea > /dev/null || (echo "ERROR: the Zarf git-server was not found. Either Zarf was not initialized or it was initialized without the git-server component" && exit 1)
