#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template zot-test manifests)"
  CONFIG_JSON="$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ConfigMap" and .metadata.name == "zot-config") | .data["config.json"]
  ' -)"
  export CONFIG_JSON
}

@test "grants ci-readonly whole-registry read access without altering the ci admin policy" {
  ci_readonly_users=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["**"].policies[0].users')
  ci_readonly_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["**"].policies[0].actions')
  default_policy=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["**"].defaultPolicy')
  admin_users=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.adminPolicy.users')
  admin_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.adminPolicy.actions')

  [ "$ci_readonly_users" = '["ci-readonly"]' ]
  [ "$ci_readonly_actions" = '["read"]' ]
  [ "$default_policy" = "[]" ]
  [ "$admin_users" = '["ci"]' ]
  [ "$admin_actions" = '["read","create","update","delete"]' ]
}
