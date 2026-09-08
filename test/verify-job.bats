#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template zot-test manifests)"
  export RENDERED
}

@test "verify job runs as the zot-verify ServiceAccount" {
  sa=$(echo "$RENDERED" | yq eval-all 'select(.kind == "Job" and .metadata.name == "zot-verify") | .spec.template.spec.serviceAccountName' -)
  [ "$sa" = "zot-verify" ]
}

@test "verify job has OPENBAO_ADDR set so it can fetch the ci-readonly test credential" {
  addr=$(echo "$RENDERED" | yq eval-all 'select(.kind == "Job" and .metadata.name == "zot-verify") | .spec.template.spec.containers[0].env[] | select(.name == "OPENBAO_ADDR") | .value' -)
  [ -n "$addr" ]
}

@test "zot-verify ServiceAccount exists in the zot namespace" {
  ns=$(echo "$RENDERED" | yq eval-all 'select(.kind == "ServiceAccount" and .metadata.name == "zot-verify") | .metadata.namespace' -)
  [ "$ns" = "zot" ]
}
