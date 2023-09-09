#!/usr/bin/env bash

# Script that will update the server's /etc/hosts file with the various ingress gateway IP addresses

# enable common error handling options
set -o errexit
set -o nounset
set -o pipefail

admin_ingressgateway_ip=$(kubectl get svc admin-ingressgateway -n istio-system -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
keycloak_ingressgateway_ip=$(kubectl get svc keycloak-ingressgateway -n istio-system -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
tenant_ingressgateway_ip=$(kubectl get svc tenant-ingressgateway -n istio-system -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')

grep -qxF "${admin_ingressgateway_ip} kiali.bigbang.dev grafana.bigbang.dev neuvector.bigbang.dev tracing.bigbang.dev adminneedle.bigbang.dev" /etc/hosts || echo "${admin_ingressgateway_ip} kiali.bigbang.dev grafana.bigbang.dev neuvector.bigbang.dev tracing.bigbang.dev adminneedle.bigbang.dev" | tee -a /etc/hosts
grep -qxF "${keycloak_ingressgateway_ip} keycloak.bigbang.dev keycloakneedle.bigbang.dev" /etc/hosts || echo "${keycloak_ingressgateway_ip} keycloak.bigbang.dev keycloakneedle.bigbang.dev" | tee -a /etc/hosts
grep -qxF "${tenant_ingressgateway_ip} podinfo.bigbang.dev tenantneedle.bigbang.dev" /etc/hosts || echo "${tenant_ingressgateway_ip} podinfo.bigbang.dev tenantneedle.bigbang.dev" | tee -a /etc/hosts
