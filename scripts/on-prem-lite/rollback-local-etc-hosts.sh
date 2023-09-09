#!/usr/bin/env bash

# Script that will rollback the local /etc/hosts file

# enable common error handling options
set -o errexit
set -o nounset
set -o pipefail

SED_INPLACE=$(sed --version 2>&1 | grep -q 'GNU' && echo "-i" || echo "-i ''")

# shellcheck disable=SC2086
sed ${SED_INPLACE} '/adminneedle\.bigbang\.dev/d' /etc/hosts
# shellcheck disable=SC2086
sed ${SED_INPLACE} '/keycloakneedle\.bigbang\.dev/d' /etc/hosts
# shellcheck disable=SC2086
sed ${SED_INPLACE} '/tenantneedle\.bigbang\.dev/d' /etc/hosts
