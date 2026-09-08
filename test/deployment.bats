#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template zot-test manifests)"
  export RENDERED
}

@test "renders restartTrigger as the pod template's restart-trigger annotation" {
  annotation=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "Deployment" and .metadata.name == "zot") | .spec.template.metadata.annotations["restart-trigger"]
  ' -)
  [ "$annotation" = "2026-09-08-htpasswd-merge-mechanism-rebuilt" ]
}
