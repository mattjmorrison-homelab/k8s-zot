#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

@test "check.yml exists" {
  [ -f .github/workflows/check.yml ]
}

@test "check.yml triggers on pull_request" {
  run bash -c "grep -c 'pull_request:' .github/workflows/check.yml"
  [ "$status" -eq 0 ]
}

@test "check.yml checks out the repo" {
  run bash -c "grep -c 'actions/checkout@' .github/workflows/check.yml"
  [ "$status" -eq 0 ]
}

@test "check.yml uses the shared actions-helm dry-run action" {
  run bash -c "grep -c 'mattjmorrison-homelab/actions-helm@' .github/workflows/check.yml"
  [ "$status" -eq 0 ]
}

@test "check.yml configures actions-helm with the zot namespace" {
  run bash -c "grep -c 'namespace: zot' .github/workflows/check.yml"
  [ "$status" -eq 0 ]
}

@test "check.yml disables the actions-helm dry-run step" {
  run bash -c "grep -cE 'dry-run: \"?false\"?' .github/workflows/check.yml"
  [ "$status" -eq 0 ]
}
