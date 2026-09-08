#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."

  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"

  cat > "$MOCK_BIN/curl" <<'SCRIPT'
#!/bin/sh
# Minimal curl mock: GET-style calls (no -X) print $MOCK_GET_RESPONSE, except
# a request for the k8s-zot/htpasswd path specifically prints
# $MOCK_HTPASSWD_RESPONSE if set (falls back to $MOCK_GET_RESPONSE otherwise,
# so tests that never set it keep the original single-response behavior).
# POST calls (-X POST) append their -d payload to $MOCK_POST_LOG instead
# of hitting a real server.
is_post=0
for arg in "$@"; do
  [ "$arg" = "-X" ] && is_post=1
done
if [ "$is_post" = "1" ]; then
  prev=""
  for arg in "$@"; do
    [ "$prev" = "-d" ] && echo "$arg" >> "$MOCK_POST_LOG"
    prev="$arg"
  done
  exit 0
fi
url="$*"
case "$url" in
  *k8s-zot/htpasswd*) printf '%s' "${MOCK_HTPASSWD_RESPONSE:-$MOCK_GET_RESPONSE}" ;;
  *) printf '%s' "$MOCK_GET_RESPONSE" ;;
esac
SCRIPT
  chmod +x "$MOCK_BIN/curl"

  cat > "$MOCK_BIN/openssl" <<'SCRIPT'
#!/bin/sh
echo "$MOCK_GENERATED_PASSWORD"
SCRIPT
  chmod +x "$MOCK_BIN/openssl"

  cat > "$MOCK_BIN/htpasswd" <<'SCRIPT'
#!/bin/sh
# Mock: htpasswd -nbB <user> <password> -> deterministic "user:hashed-<password>"
shift
echo "$1:hashed-$2"
SCRIPT
  chmod +x "$MOCK_BIN/htpasswd"

  export PATH="$MOCK_BIN:$PATH"
  export OPENBAO_ADDR="http://openbao.test"
  export VAULT_TOKEN_SELF="fake-token"
  MOCK_POST_LOG="$BATS_TEST_TMPDIR/post.log"
  export MOCK_POST_LOG
  : > "$MOCK_POST_LOG"

  export BOOTSTRAP_SH_SOURCED=1
  . manifests/scripts/bootstrap.sh
  set +eu
}

@test "ensure_password skips when a value already exists" {
  export MOCK_GET_RESPONSE='{"data":{"data":{"value":"already-here"}}}'
  run ensure_password "service/k8s-zot/k8s-garage/pull-helm-libs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already has a value, skipping"* ]]
  [ ! -s "$MOCK_POST_LOG" ]
}

@test "ensure_password generates and stores a password when none exists" {
  export MOCK_GET_RESPONSE='{}'
  export MOCK_GENERATED_PASSWORD='fake-generated-password'
  run ensure_password "service/k8s-zot/k8s-garage/pull-helm-libs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Stored new value"* ]]
  grep -q 'fake-generated-password' "$MOCK_POST_LOG"
}

@test "merge_htpasswd preserves the legacy blob untouched and appends one hashed line per consumer with a stored password" {
  export MOCK_HTPASSWD_RESPONSE='{"data":{"data":{"value":"ci:legacyhash1\nci-readonly:legacyhash2"}}}'
  export MOCK_GET_RESPONSE='{"data":{"data":{"value":"secret-pw"}}}'
  export SERVICE_CONSUMERS_JSON='[{"name":"k8s-garage","cred":"pull-helm-libs"}]'
  out="$BATS_TEST_TMPDIR/merged.htpasswd"
  run merge_htpasswd "$out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Wrote merged htpasswd"* ]]
  grep -q '^ci:legacyhash1$' "$out"
  grep -q '^ci-readonly:legacyhash2$' "$out"
  grep -q '^k8s-garage:hashed-secret-pw$' "$out"
  posted=$(cat "$MOCK_POST_LOG")
  [[ "$posted" == *"legacyhash1"* ]]
  [[ "$posted" == *"k8s-garage:hashed-secret-pw"* ]]
}

@test "merge_htpasswd skips a consumer with no password yet, without failing the whole write" {
  export MOCK_HTPASSWD_RESPONSE='{"data":{"data":{"value":"ci:legacyhash1"}}}'
  export MOCK_GET_RESPONSE='{}'
  export SERVICE_CONSUMERS_JSON='[{"name":"k8s-graphql-router","cred":"zot-pull"}]'
  out="$BATS_TEST_TMPDIR/merged.htpasswd"
  run merge_htpasswd "$out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No password yet for k8s-graphql-router"* ]]
  [[ "$output" == *"Wrote merged htpasswd"* ]]
  grep -q '^ci:legacyhash1$' "$out"
  ! grep -q 'k8s-graphql-router' "$out"
  [ -s "$MOCK_POST_LOG" ]
}
