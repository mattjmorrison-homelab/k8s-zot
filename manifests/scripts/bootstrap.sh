#!/bin/sh
set -eu

# 404s if the path doesn't exist yet at all -- treat that the same as
# "no value". Idempotent: only ever writes a password once per path.
ensure_password() {
  path="$1"
  existing=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN_SELF" \
    "$OPENBAO_ADDR/v1/kv/data/homelab/$path" || echo '{}')
  value=$(echo "$existing" | jq -r '.data.data.value // empty')
  if [ -n "$value" ]; then
    echo "$path already has a value, skipping."
    return
  fi
  echo "No value at $path, generating..."
  password=$(openssl rand -base64 24)
  curl -sf -X POST -H "X-Vault-Token: $VAULT_TOKEN_SELF" \
    -H "Content-Type: application/json" \
    -d "{\"data\": {\"value\": \"$password\"}}" \
    "$OPENBAO_ADDR/v1/kv/data/homelab/$path" > /dev/null
  echo "Stored new value at $path."
}

# Lookup-free by design -- unlike the reverted secret-htpasswd.yaml
# (Helm's `lookup` against a live cluster Secret, which silently
# returned empty when ArgoCD's repo-server lacked RBAC, wiping out
# every user including the admin `ci` -- see k8s-zot#5's revert), this
# reads and writes only through OpenBao's own API, using this script's
# own already-granted zot-bootstrap identity. The legacy ci/ci-readonly
# blob is fetched and re-written completely untouched, unconditionally
# -- a single consumer's password fetch failing skips only that one
# line, never the whole write.
merge_htpasswd() {
  out="$1"
  existing=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN_SELF" \
    "$OPENBAO_ADDR/v1/kv/data/homelab/k8s-zot/htpasswd" || echo '{}')
  echo "$existing" | jq -r '.data.data.value // empty' > "$out"

  echo "$SERVICE_CONSUMERS_JSON" | jq -c '.[]' |
    while IFS= read -r consumer; do
      name=$(echo "$consumer" | jq -r '.name')
      cred=$(echo "$consumer" | jq -r '.cred')
      password_data=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN_SELF" \
        "$OPENBAO_ADDR/v1/kv/data/homelab/service/k8s-zot/$name/$cred" || echo '{}')
      password=$(echo "$password_data" | jq -r '.data.data.value // empty')
      if [ -z "$password" ]; then
        echo "No password yet for $name, skipping its htpasswd line." >&2
        continue
      fi
      htpasswd -nbB "$name" "$password" >> "$out"
    done

  merged=$(cat "$out")
  payload=$(jq -n --arg v "$merged" '{data: {value: $v}}')
  curl -sf -X POST -H "X-Vault-Token: $VAULT_TOKEN_SELF" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$OPENBAO_ADDR/v1/kv/data/homelab/k8s-zot/htpasswd" > /dev/null
  echo "Wrote merged htpasswd blob to kv/homelab/k8s-zot/htpasswd."
}

main() {
  apk add --no-cache curl jq openssl apache2-utils >/dev/null

  SA_JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  VAULT_TOKEN_SELF=$(curl -sf -X POST "$OPENBAO_ADDR/v1/auth/kubernetes/login" \
    -d "{\"jwt\": \"$SA_JWT\", \"role\": \"zot-bootstrap\"}" | jq -r .auth.client_token)
  export VAULT_TOKEN_SELF

  echo "$SERVICE_CONSUMERS_JSON" | jq -r '.[] | "service/k8s-zot/\(.name)/\(.cred)"' |
    while IFS= read -r path; do
      ensure_password "$path"
    done

  merge_htpasswd "$(mktemp)"
}

# Guarded so test/bootstrap-script.bats can source this file to exercise
# ensure_password directly (with curl/openssl mocked) without also
# running main's real OpenBao login.
if [ "${BOOTSTRAP_SH_SOURCED:-0}" != "1" ]; then
  main
fi
