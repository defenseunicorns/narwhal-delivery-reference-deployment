#!/usr/bin/env bash

# Script that will update CoreDNS with the Keycloak ingress gateway IP address

# enable common error handling options
set -o errexit
set -o nounset
set -o pipefail

keycloak_ingressgateway_ip=$(kubectl get svc keycloak-ingressgateway -n istio-system -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
existing_node_hosts=$(kubectl get cm coredns -n kube-system -o jsonpath='{.data.NodeHosts}')
kubectl get cm coredns -n kube-system -o jsonpath='{.data.NodeHosts}' | grep -q "${keycloak_ingressgateway_ip} keycloak.bigbang.dev" || kubectl patch cm coredns -n kube-system --type='json' -p="[{\"op\": \"replace\", \"path\": \"/data/NodeHosts\", \"value\":\"${existing_node_hosts}\n${keycloak_ingressgateway_ip} keycloak.bigbang.dev\"}]"
kubectl rollout restart deployment coredns -n kube-system
