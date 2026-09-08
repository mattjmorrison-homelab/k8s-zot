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

@test "zot's pod runs an init container that waits for the htpasswd ExternalSecret to refresh before the main container starts" {
  name=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "Deployment" and .metadata.name == "zot") | .spec.template.spec.initContainers[0].name
  ' -)
  [ "$name" = "wait-for-htpasswd-refresh" ]
}

@test "the refresh init container mounts the wait-for-htpasswd-refresh script" {
  cm=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "Deployment" and .metadata.name == "zot") |
    .spec.template.spec.volumes[] | select(.name == "refresh-script") | .configMap.name
  ' -)
  [ "$cm" = "zot-refresh-htpasswd-script" ]
}

@test "zot's ServiceAccount has a Role/RoleBinding scoped to get+patch only the zot-htpasswd ExternalSecret" {
  verbs=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "Role" and .metadata.name == "zot-htpasswd-refresh") | .rules[0].verbs | join(",")
  ' -)
  [ "$verbs" = "get,patch" ]

  resource_names=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "Role" and .metadata.name == "zot-htpasswd-refresh") | .rules[0].resourceNames | join(",")
  ' -)
  [ "$resource_names" = "zot-htpasswd" ]

  subject_sa=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "RoleBinding" and .metadata.name == "zot-htpasswd-refresh") | .subjects[0].name
  ' -)
  [ "$subject_sa" = "zot" ]
}
