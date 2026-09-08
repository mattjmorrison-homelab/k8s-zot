#!/bin/sh
set -eu

apk add --no-cache curl jq >/dev/null

KUBE_API="https://kubernetes.default.svc"
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
ES_URL="$KUBE_API/apis/external-secrets.io/v1/namespaces/$NAMESPACE/externalsecrets/zot-htpasswd"

k8s_get() {
  curl -sf --cacert "$CACERT" -H "Authorization: Bearer $TOKEN" "$ES_URL"
}

# The bootstrap job's PreSync write and this pod's Secret mount are on two
# completely independent clocks -- ExternalSecret only refreshes on its own
# refreshInterval timer, not on ArgoCD's hook phases. Forcing a real refresh
# here (instead of trusting the timer) is what closes that race. Any
# annotation/label/spec edit changes the metadata hash ESO compares against
# status.syncedResourceVersion, forcing an immediate reconcile regardless of
# refreshInterval -- verified against the live v2.10.0 controller source
# (shouldRefreshPeriodic), not assumed.
before=$(k8s_get | jq -r '.status.refreshTime // empty')

patch=$(jq -n --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{metadata:{annotations:{"homelab.morrisons.site/force-refresh": $t}}}')
curl -sf --cacert "$CACERT" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/merge-patch+json" \
  -X PATCH -d "$patch" "$ES_URL" > /dev/null

echo "Waiting for zot-htpasswd ExternalSecret to refresh..."
i=0
while [ "$i" -lt 30 ]; do
  after=$(k8s_get | jq -r '.status.refreshTime // empty')
  if [ -n "$after" ] && [ "$after" != "$before" ]; then
    echo "Refreshed at $after."
    exit 0
  fi
  i=$((i + 1))
  sleep 2
done

echo "FAIL: zot-htpasswd did not refresh within timeout." >&2
exit 1
