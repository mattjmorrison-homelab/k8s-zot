#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template zot-test manifests)"
  export RENDERED
}

@test "bootstrap job runs as the zot-bootstrap ServiceAccount" {
  sa=$(echo "$RENDERED" | yq eval-all 'select(.kind == "Job" and .metadata.name == "zot-bootstrap-secrets") | .spec.template.spec.serviceAccountName' -)
  [ "$sa" = "zot-bootstrap" ]
}

@test "bootstrap job passes serviceConsumers through as SERVICE_CONSUMERS_JSON" {
  json=$(echo "$RENDERED" | yq eval-all 'select(.kind == "Job" and .metadata.name == "zot-bootstrap-secrets") | .spec.template.spec.containers[0].env[] | select(.name == "SERVICE_CONSUMERS_JSON") | .value' -)
  name=$(echo "$json" | jq -r '.[0].name')
  cred=$(echo "$json" | jq -r '.[0].cred')
  [ "$name" = "k8s-garage" ]
  [ "$cred" = "pull-helm-libs" ]
}

@test "bootstrap ConfigMap loads the real bootstrap.sh file, not an inline copy" {
  script=$(echo "$RENDERED" | yq eval-all 'select(.kind == "ConfigMap" and .metadata.name == "zot-bootstrap-secrets-script") | .data."bootstrap.sh"' -)
  [[ "$script" == *"ensure_password()"* ]]
  diff <(echo "$script") manifests/scripts/bootstrap.sh
}

@test "verify script ConfigMap does not pick up bootstrap.sh" {
  keys=$(echo "$RENDERED" | yq eval-all 'select(.kind == "ConfigMap" and .metadata.name == "zot-verify-script") | .data | keys | .[]' -)
  [ "$keys" = "verify.sh" ]
}

@test "zot-bootstrap ServiceAccount is a PreSync hook, applying before the job that depends on it" {
  hook=$(echo "$RENDERED" | yq eval-all 'select(.kind == "ServiceAccount" and .metadata.name == "zot-bootstrap") | .metadata.annotations["argocd.argoproj.io/hook"]' -)
  wave=$(echo "$RENDERED" | yq eval-all 'select(.kind == "ServiceAccount" and .metadata.name == "zot-bootstrap") | .metadata.annotations["argocd.argoproj.io/sync-wave"]' -)
  # A plain resource's sync-wave never places it ahead of a PreSync hook --
  # phase is ordered before wave, so this SA must be a PreSync hook itself.
  [ "$hook" = "PreSync" ]
  [ -n "$wave" ]
  [ "$wave" -lt 0 ]
}
