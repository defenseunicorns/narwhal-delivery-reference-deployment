#!/bin/bash

# This test expects a running deployment, with https://keycloak.bigbang.dev and https://podinfo.bigbang.dev accessible from the local machine

# Function to print an error message and exit
error_exit() {
    echo "$1" 1>&2
    exit 1
}

# Make sure Keycloak is accessible
if ! curl -o /dev/null -s -w "%{http_code}" "https://keycloak.bigbang.dev/auth/realms/baby-yoda" | grep -q "200"; then
    error_exit "Error: keycloak.bigbang.dev is not accessible"
fi

# Make sure Podinfo redirects to Keycloak appropriately
if ! curl -sI "https://podinfo.bigbang.dev" | grep "location" | grep -q "https://keycloak.bigbang.dev/auth/realms/baby-yoda/protocol/openid-connect/auth"; then
    error_exit "Error: podinfo.bigbang.dev is not redirecting to keycloak.bigbang.dev"
fi

echo "Tests passed successfully!"
