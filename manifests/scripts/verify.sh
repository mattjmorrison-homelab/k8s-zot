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

# Real authenticated request as zot-verify -- its own dedicated,
# narrowly-scoped account (not a shared one like ci-readonly), generated
# and stored the same way as every other real consumer. Catches a broken
# htpasswd merge (empty blob, or a missing/garbled entry) immediately,
# instead of silently, which is exactly the class of outage a prior
# lookup-based merge attempt caused (see k8s-zot#5's revert).
SA_JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CLIENT_TOKEN=$(curl -sf -X POST "$OPENBAO_ADDR/v1/auth/kubernetes/login" \
  -d "{\"jwt\": \"$SA_JWT\", \"role\": \"zot-verify\"}" | jq -r .auth.client_token)
ZOT_VERIFY_PASSWORD=$(curl -sf -H "X-Vault-Token: $CLIENT_TOKEN" \
  "$OPENBAO_ADDR/v1/kv/data/homelab/service/k8s-zot/zot-verify/verify-password" | jq -r '.data.data.value')

TEST_REPO="charts/k8s-ci-rbac"
AUTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "zot-verify:$ZOT_VERIFY_PASSWORD" \
  "https://registry.morrisons.site/v2/$TEST_REPO/tags/list")

if [ "$AUTH_STATUS" != "200" ]; then
  echo "FAIL: zot-verify authentication against /v2/$TEST_REPO/tags/list returned $AUTH_STATUS, expected 200"
  exit 1
fi

echo "PASS: zot-verify authenticated successfully"
