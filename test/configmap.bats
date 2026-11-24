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

@test "k8s-argocd-image-updater also gets read on graph-ad-reporter's and ui-ad-reporter's image repositories" {
  graph_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["graph-ad-reporter"].policies | map(select(.users == ["k8s-argocd-image-updater"]))[0].actions')
  ui_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["ui-ad-reporter"].policies | map(select(.users == ["k8s-argocd-image-updater"]))[0].actions')
  [ "$graph_actions" = '["read"]' ]
  [ "$ui_actions" = '["read"]' ]
}

@test "graph-ad-reporter gets its own publish-side accessControl block for its image repository" {
  actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["graph-ad-reporter"].policies | map(select(.users == ["graph-ad-reporter"]))[0].actions')
  [ "$actions" = '["read","create","update"]' ]
}

@test "ui-ad-reporter gets its own publish-side accessControl block for its image repository" {
  actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["ui-ad-reporter"].policies | map(select(.users == ["ui-ad-reporter"]))[0].actions')
  [ "$actions" = '["read","create","update"]' ]
}

@test "graph-ad-reporter and ui-ad-reporter also get publish-side accessControl blocks for their -test repositories, mirroring graph-hdmi-switch-test" {
  graph_test_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["graph-ad-reporter-test"].policies | map(select(.users == ["graph-ad-reporter"]))[0].actions')
  ui_test_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["ui-ad-reporter-test"].policies | map(select(.users == ["ui-ad-reporter"]))[0].actions')
  [ "$graph_test_actions" = '["read","create","update"]' ]
  [ "$ui_test_actions" = '["read","create","update"]' ]
}

@test "k8s-ad-reporter gets a read-only pull policy on both graph-ad-reporter's and ui-ad-reporter's image repositories" {
  graph_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["graph-ad-reporter"].policies | map(select(.users == ["k8s-ad-reporter"]))[0].actions')
  ui_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["ui-ad-reporter"].policies | map(select(.users == ["k8s-ad-reporter"]))[0].actions')
  [ "$graph_actions" = '["read"]' ]
  [ "$ui_actions" = '["read"]' ]
}

@test "claude-prompt-runner gets its own publish-side accessControl block for its image repository" {
  actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["claude-prompt-runner"].policies | map(select(.users == ["claude-prompt-runner"]))[0].actions')
  [ "$actions" = '["read","create","update"]' ]
}

@test "claude-prompt-runner also gets a publish-side accessControl block for its -test repository, mirroring graph-claude-test" {
  actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["claude-prompt-runner-test"].policies | map(select(.users == ["claude-prompt-runner"]))[0].actions')
  [ "$actions" = '["read","create","update"]' ]
}

@test "k8s-claude gets a read-only pull policy on both graph-claude's and claude-prompt-runner's image repositories" {
  graph_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["graph-claude"].policies | map(select(.users == ["k8s-claude"]))[0].actions')
  runner_actions=$(echo "$CONFIG_JSON" | jq -c '.http.accessControl.repositories["claude-prompt-runner"].policies | map(select(.users == ["k8s-claude"]))[0].actions')
  [ "$graph_actions" = '["read"]' ]
  [ "$runner_actions" = '["read"]' ]
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

@test "gc is enabled with a 1h interval so retention policies actually run" {
  gc=$(echo "$CONFIG_JSON" | jq '.storage.gc')
  gc_interval=$(echo "$CONFIG_JSON" | jq -r '.storage.gcInterval')
  [ "$gc" = "true" ]
  [ "$gc_interval" = "1h" ]
}

@test "retention starts in dryRun and applies to every repository" {
  dry_run=$(echo "$CONFIG_JSON" | jq '.storage.retention.dryRun')
  repositories=$(echo "$CONFIG_JSON" | jq -c '.storage.retention.policies[0].repositories')
  [ "$dry_run" = "true" ]
  [ "$repositories" = '["**"]' ]
}

@test "retention policy does not delete untagged manifests, only pr-* tags" {
  delete_untagged=$(echo "$CONFIG_JSON" | jq '.storage.retention.policies[0].deleteUntagged')
  [ "$delete_untagged" = "false" ]
}

@test "pr-* tags are matched before the catch-all so they age out instead of being kept forever" {
  first_pattern=$(echo "$CONFIG_JSON" | jq -c '.storage.retention.policies[0].keepTags[0].patterns')
  first_pushed_within=$(echo "$CONFIG_JSON" | jq -r '.storage.retention.policies[0].keepTags[0].pushedWithin')
  second_pattern=$(echo "$CONFIG_JSON" | jq -c '.storage.retention.policies[0].keepTags[1].patterns')
  keep_tags_count=$(echo "$CONFIG_JSON" | jq '.storage.retention.policies[0].keepTags | length')
  [ "$first_pattern" = '["^pr-.+$"]' ]
  [ "$first_pushed_within" = "120h" ]
  [ "$second_pattern" = '[".*"]' ]
  [ "$keep_tags_count" = "2" ]
}

@test "the catch-all keepTags entry has no age limit, so every non-pr-* tag is retained indefinitely" {
  has_pushed_within=$(echo "$CONFIG_JSON" | jq '.storage.retention.policies[0].keepTags[1] | has("pushedWithin")')
  has_pulled_within=$(echo "$CONFIG_JSON" | jq '.storage.retention.policies[0].keepTags[1] | has("pulledWithin")')
  has_most_recently_pushed=$(echo "$CONFIG_JSON" | jq '.storage.retention.policies[0].keepTags[1] | has("mostRecentlyPushedCount")')
  [ "$has_pushed_within" = "false" ]
  [ "$has_pulled_within" = "false" ]
  [ "$has_most_recently_pushed" = "false" ]
}
