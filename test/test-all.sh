#!/usr/bin/env bash

# enable common error handling options
set -o pipefail

FAILURE=0
make _test-infra-up _test-platform-up _test-mission-app-up || FAILURE=1
[[ $FAILURE -eq 0 ]] && sleep 30
[[ $FAILURE -eq 0 ]] && make _test-mission-app-test || FAILURE=1
make _test-infra-down || FAILURE=1
exit $FAILURE
