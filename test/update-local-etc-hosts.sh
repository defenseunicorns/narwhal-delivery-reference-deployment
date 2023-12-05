#!/usr/bin/env bash

# Script that will update the local /etc/hosts file with the various ingress gateway IP addresses

# enable common error handling options
set -o errexit
set -o nounset
set -o pipefail

admin_ingressgateway_ip=10.0.255.1
tenant_ingressgateway_ip=10.0.255.2
keycloak_ingressgateway_ip=10.0.255.3

grep -qxF "${admin_ingressgateway_ip} kiali.bigbang.dev grafana.bigbang.dev neuvector.bigbang.dev tracing.bigbang.dev " /etc/hosts || echo "${admin_ingressgateway_ip} kiali.bigbang.dev grafana.bigbang.dev neuvector.bigbang.dev tracing.bigbang.dev" | tee -a /etc/hosts
grep -qxF "${keycloak_ingressgateway_ip} keycloak.bigbang.dev" /etc/hosts || echo "${keycloak_ingressgateway_ip} keycloak.bigbang.dev" | tee -a /etc/hosts
grep -qxF "${tenant_ingressgateway_ip} podinfo.bigbang.dev" /etc/hosts || echo "${tenant_ingressgateway_ip} podinfo.bigbang.dev" | tee -a /etc/hosts
