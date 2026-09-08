#!/bin/sh
set -eu

apk add --no-cache curl jq >/dev/null

URL="https://registry.morrisons.site/"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL")

if [ "$STATUS" != "200" ]; then
  echo "FAIL: expected status 200 from $URL, got $STATUS"
  exit 1
fi

echo "PASS: $URL returned 200"

# Real authenticated request as ci-readonly -- catches a broken htpasswd
# merge (empty blob, or a missing/garbled ci-readonly line) immediately,
# instead of silently, which is exactly the class of outage a prior
# lookup-based merge attempt caused (see k8s-zot#5's revert). The
# plaintext password used here is a deliberate second copy of what's
# already bcrypt-hashed inside the htpasswd blob -- see admin-openbao's
# locals.tf for why.
SA_JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CLIENT_TOKEN=$(curl -sf -X POST "$OPENBAO_ADDR/v1/auth/kubernetes/login" \
  -d "{\"jwt\": \"$SA_JWT\", \"role\": \"zot-verify\"}" | jq -r .auth.client_token)
CI_READONLY_PASSWORD=$(curl -sf -H "X-Vault-Token: $CLIENT_TOKEN" \
  "$OPENBAO_ADDR/v1/kv/data/homelab/k8s-zot/ci-readonly-password" | jq -r '.data.data.value')

AUTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "ci-readonly:$CI_READONLY_PASSWORD" \
  "https://registry.morrisons.site/v2/_catalog")

if [ "$AUTH_STATUS" != "200" ]; then
  echo "FAIL: ci-readonly authentication against /v2/_catalog returned $AUTH_STATUS, expected 200"
  exit 1
fi

echo "PASS: ci-readonly authenticated successfully"
