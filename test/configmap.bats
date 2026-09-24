#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template zot-test manifests)"
  CONFIG_JSON="$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ConfigMap" and .metadata.name == "zot-config") | .data["config.json"]
  ' -)"
  export CONFIG_JSON
}

@test "no whole-registry ci-readonly wildcard and no ci adminPolicy -- both retired, zero live consumers left" {
  wildcard=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories | has("**")')
  has_admin_policy=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl | has("adminPolicy")')

  [ "$wildcard" = "false" ]
  [ "$has_admin_policy" = "false" ]
}

@test "a consumer with multiple repositories gets a distinct accessControl block for each, all naming the same user" {
  graph_hdmi_users=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["graph-hdmi-switch"].policies | map(select(.users == ["graph-hdmi-switch"])) | length')
  graph_hdmi_test_users=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["graph-hdmi-switch-test"].policies | map(select(.users == ["graph-hdmi-switch"])) | length')
  [ "$graph_hdmi_users" = "1" ]
  [ "$graph_hdmi_test_users" = "1" ]
}

@test "a repository shared by multiple consumers groups all their policies under one key, not duplicate keys" {
  # graph-router is read by k8s-graphql-router and k8s-argocd-image-updater,
  # and published (read+create+update) by graph-router's own CI -- three
  # distinct consumers, one repository key.
  policy_count=$(echo "$CONFIG_JSON" | jq '.http.accessControl.repositories["graph-router"].policies | length')
  publisher_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["graph-router"].policies | map(select(.users == ["graph-router"]))[0].actions')
  [ "$policy_count" = "3" ]
  [ "$publisher_actions" = '["read","create","update"]' ]
}
