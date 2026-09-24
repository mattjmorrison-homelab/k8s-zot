#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template zot-test manifests)"
  export RENDERED
}

@test "each service-credential ExternalSecret carries refreshTrigger as its refresh-trigger annotation" {
  count=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ExternalSecret" and .metadata.name == "zot-service-cred-k8s-garage") | .metadata.annotations["refresh-trigger"]
  ' -)
  [ "$count" = "2026-09-24-post-incident-recovery" ]
}

@test "every service-credential ExternalSecret gets the same refresh-trigger value, not just one" {
  matches=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ExternalSecret" and (.metadata.name | test("^zot-service-cred-"))) | .metadata.annotations["refresh-trigger"]
  ' -)
  count=$(echo "$matches" | grep -c "2026-09-24-post-incident-recovery")
  [ "$count" = "10" ]
}
