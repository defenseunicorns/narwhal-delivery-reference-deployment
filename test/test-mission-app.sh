#!/bin/bash

# This test expects a running deployment, with https://keycloak.bigbang.dev and https://podinfo.bigbang.dev accessible from the local machine.
# If using a different domain, pass the domain (bigbang.dev in the above examples) as the first argument.
DOMAIN=$1
ARGS="--cacert /home/ssm-user/narwhal-delivery-reference-deployment/tls.cert"
if [ -z "$DOMAIN" ]; then
  DOMAIN="bigbang.dev"
  ARGS=""
fi
echo "Running keycloak / mission app tests for domain: $DOMAIN, $ARGS"


# Function to print an error message and exit
error_exit() {
    echo "$1" 1>&2
    exit 1
}

# Make sure Keycloak is accessible
if ! curl -o /dev/null -s -w "%{http_code}" $ARGS "https://keycloak.$DOMAIN/auth/realms/baby-yoda" | grep -q "200"; then
    echo "$(curl -s -w "%{http_code}" $ARGS https://keycloak.dextest.dev/auth/realms/baby-yoda)";
    error_exit "Error: keycloak.$DOMAIN is not accessible"
fi

# Make sure Podinfo redirects to Keycloak appropriately
if ! curl -sI $ARGS "https://podinfo.$DOMAIN" | grep "location" | grep -q "https://keycloak.$DOMAIN/auth/realms/baby-yoda/protocol/openid-connect/auth"; then
    error_exit "Error: podinfo.$DOMAIN is not redirecting to keycloak.$DOMAIN"
fi

echo "Tests passed successfully!"
