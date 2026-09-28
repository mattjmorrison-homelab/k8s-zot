#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template zot-test manifests)"
  CONFIG_JSON="$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ConfigMap" and .metadata.name == "zot-config") | .data["config.json"]
  ' -)"
  export CONFIG_JSON
}

@test "http read/write timeouts default to 300s, well above zot's 60s default" {
  read_timeout=$(echo "$CONFIG_JSON" | jq -r '.http.readTimeout')
  write_timeout=$(echo "$CONFIG_JSON" | jq -r '.http.writeTimeout')

  [ "$read_timeout" = "300s" ]
  [ "$write_timeout" = "300s" ]
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

@test "app-backstage gets its own publish-side accessControl block for its image repository" {
  backstage_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["app-backstage"].policies | map(select(.users == ["app-backstage"]))[0].actions')
  [ "$backstage_actions" = '["read","create","update"]' ]
}

@test "docker-backstage gets its own publish-side accessControl block for its image repository" {
  backstage_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["docker-backstage"].policies | map(select(.users == ["docker-backstage"]))[0].actions')
  [ "$backstage_actions" = '["read","create","update"]' ]
}

@test "app-backstage also gets a policy on docker-backstage's repository, so its CI can pull the base image" {
  actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["docker-backstage"].policies | map(select(.users == ["app-backstage"]))[0].actions')
  [ "$actions" = '["read","create","update"]' ]
}

@test "app-backstage-test repository no longer has any accessControl block -- the test stage was dropped, nothing pushes there anymore" {
  repo=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories | has("app-backstage-test")')
  [ "$repo" = "false" ]
}

@test "k8s-backstage gets a read-only pull policy on app-backstage's image repository" {
  actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["app-backstage"].policies | map(select(.users == ["k8s-backstage"]))[0].actions')
  [ "$actions" = '["read"]' ]
}

@test "k8s-argocd-image-updater also gets read on app-backstage's image repository" {
  actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["app-backstage"].policies | map(select(.users == ["k8s-argocd-image-updater"]))[0].actions')
  [ "$actions" = '["read"]' ]
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
