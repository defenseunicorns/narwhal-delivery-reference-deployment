package e2e_test

import (
	"github.com/stretchr/testify/require"
	"os/exec"
	"testing"
)

func TestOnPremLite(t *testing.T) { //nolint:paralleltest
	// This test expects a running on-prem-lite deployment, with https://keycloak.bigbang.dev and https://podinfo.bigbang.dev accessible from the local machine

	// Make sure Keycloak is accessible
	cmdStr := `curl -o /dev/null -s -w "%{http_code}" "https://keycloak.bigbang.dev/auth/realms/baby-yoda" | grep -q "200"
`
	err := exec.Command("bash", "-c", cmdStr).Run()
	require.NoError(t, err, "keycloak.bigbang.dev is not accessible")

	// Make sure Podinfo redirects to Keycloak appropriately
	cmdStr = `curl -sI "https://podinfo.bigbang.dev" | grep "location" | grep -q "https://keycloak.bigbang.dev/auth/realms/baby-yoda/protocol/openid-connect/auth"`
	err = exec.Command("bash", "-c", cmdStr).Run()
	require.NoError(t, err, "podinfo.bigbang.dev is not redirecting to keycloak.bigbang.dev")
}
