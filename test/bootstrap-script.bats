#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."

  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"

  cat > "$MOCK_BIN/curl" <<'SCRIPT'
#!/bin/sh
# Minimal curl mock: GET-style calls (no -X) print $MOCK_GET_RESPONSE.
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
printf '%s' "$MOCK_GET_RESPONSE"
SCRIPT
  chmod +x "$MOCK_BIN/curl"

  cat > "$MOCK_BIN/openssl" <<'SCRIPT'
#!/bin/sh
echo "$MOCK_GENERATED_PASSWORD"
SCRIPT
  chmod +x "$MOCK_BIN/openssl"

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
