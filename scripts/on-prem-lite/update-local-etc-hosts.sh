#!/usr/bin/env bash

# Script that will update the local /etc/hosts file with the various ingress gateway IP addresses

# enable common error handling options
set -o errexit
set -o nounset
set -o pipefail

parent_path=$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)
admin_ingressgateway_ip=$(cd "${parent_path}/../.." && make --silent _on-prem-lite-get-admin-ingressgateway-ip)
keycloak_ingressgateway_ip=$(cd "${parent_path}/../.." && make --silent _on-prem-lite-get-keycloak-ingressgateway-ip)
tenant_ingressgateway_ip=$(cd "${parent_path}/../.." && make --silent _on-prem-lite-get-tenant-ingressgateway-ip)

grep -qxF "${admin_ingressgateway_ip} kiali.bigbang.dev grafana.bigbang.dev neuvector.bigbang.dev tracing.bigbang.dev adminneedle.bigbang.dev" /etc/hosts || echo "${admin_ingressgateway_ip} kiali.bigbang.dev grafana.bigbang.dev neuvector.bigbang.dev tracing.bigbang.dev adminneedle.bigbang.dev" | tee -a /etc/hosts
grep -qxF "${keycloak_ingressgateway_ip} keycloak.bigbang.dev keycloakneedle.bigbang.dev" /etc/hosts || echo "${keycloak_ingressgateway_ip} keycloak.bigbang.dev keycloakneedle.bigbang.dev" | tee -a /etc/hosts
grep -qxF "${tenant_ingressgateway_ip} podinfo.bigbang.dev tenantneedle.bigbang.dev" /etc/hosts || echo "${tenant_ingressgateway_ip} podinfo.bigbang.dev tenantneedle.bigbang.dev" | tee -a /etc/hosts
