# k8s-zot

[Zot](https://zotregistry.dev/) — self-hosted OCI registry for pulling and
pushing container images. registry.morrisons.site

## Users

- **`ci`** — admin, blanket read/create/update/delete across the whole
  registry. Used by every repo's publish workflow today.
- **`ci-readonly`** — read-only access to all repositories via the `**`
  wildcard. Intended for pull-only consumers — image pull secrets,
  `homelab-woodpecker`'s pull config, etc.
- Per-entry in `manifests/values.yaml`'s `serviceConsumers` — a
  dedicated user scoped to exactly the repository path(s) it needs
  (`repositories`, a list — some consumers need more than one), with
  `actions` defaulting to read-only and set to read+create+update for
  consumers that publish their own image/chart. Password is generated
  by the `zot-bootstrap` PreSync job (`manifests/scripts/bootstrap.sh`)
  and stored in OpenBao at `kv/homelab/service/k8s-zot/<name>/<cred>`.
  The same script then fetches every registered consumer's password
  back, bcrypt-hashes each with `htpasswd -nbB`, and merges the result
  with the legacy `ci`/`ci-readonly` lines into one combined blob written
  back to `kv/homelab/k8s-zot/htpasswd` -- entirely through OpenBao's own
  API, no Helm `lookup` involved (see below for why that matters). Adding
  a new consumer is a `serviceConsumers` entry plus an `accessControl`
  repository grant — no manual credential handling.

`ci`/`ci-readonly` passwords live in OpenBao at `kv/homelab/k8s-zot/htpasswd`
property `value` (a combined htpasswd blob). The legacy lines within that
blob are still regenerated manually, out-of-band; only the per-consumer
lines are appended automatically by the merge described above.

An earlier attempt at this merge (`secret-htpasswd.yaml`) used Helm's
`lookup` function against a live cluster Secret at template-render
time. ArgoCD's repo-server lacked RBAC to read Secrets in this
namespace, so `lookup` silently returned empty, the rendered Secret came
out completely empty, and every user — including the admin `ci` — got
locked out (see the revert in this repo's history). The current
mechanism avoids this entirely by never using `lookup`: the merge runs
inside the bootstrap script itself, which already has real OpenBao
read/write access via its own `zot-bootstrap` identity.

The `defaultPolicy: []` ensures no user gains implicit access beyond their
explicit policy. Per-repository scoping of *publish* credentials (not just
read) is what the `serviceConsumers` mechanism above now provides for every
real consumer -- previously tracked as a TODO, since closed.

## Post-deploy verification

`zot-verify` (PostSync, `manifests/scripts/verify.sh`) does two checks:
a plain HTTP request confirming the registry itself is up, and a *real
authenticated request* as `zot-verify` against
`/v2/charts/k8s-ci-rbac/tags/list` — this is what actually catches a
broken htpasswd merge (an empty blob, or a garbled/missing entry),
immediately, instead of silently.

`zot-verify` is its own entry in `serviceConsumers` above, same as every
real consumer — a dedicated, narrowly-scoped account used for nothing
except this one check, not a reuse of the shared `ci-readonly` account
(which other real consumers also rely on). Its password is generated
and stored the normal way by `zot-bootstrap`, no manual population or
plaintext-duplication needed.

## ExternalSecret-refresh race (fixed)

`zot-htpasswd`'s `ExternalSecret` refreshes on its own independent
`refreshInterval: 1h` timer, completely decoupled from ArgoCD's
PreSync/Sync/PostSync hook ordering. The PreSync bootstrap job can write a
fresh merged htpasswd blob to OpenBao, and a new `zot` pod can start (via
`restartTrigger`) immediately after, without the mounted Secret actually
having picked up that fresh write yet -- confirmed live: the bootstrap job
reported a successful merge, but the pod mounted stale content, and the
PostSync verify job correctly failed with 401 as a result.

Fixed with a `wait-for-htpasswd-refresh` init container on `zot`'s own
Deployment (`manifests/scripts/wait-for-htpasswd-refresh.sh`), which runs
before the main container on every pod start. It patches an annotation on
the `zot-htpasswd` `ExternalSecret` (any metadata/spec edit changes the hash
External Secrets Operator compares against `status.syncedResourceVersion`,
forcing an immediate reconcile regardless of `refreshInterval` -- verified
against the live v2.10.0 controller source, not assumed) and polls
`status.refreshTime` until it advances past its pre-patch value, using raw
calls against the in-cluster Kubernetes API (the pod's own ServiceAccount
token + CA bundle via `curl`, no `kubectl` binary, matching this repo's
existing style). `zot`'s ServiceAccount has a narrowly-scoped `Role`/
`RoleBinding` (`manifests/templates/rbac-zot-refresh.yaml`) granting only
`get`/`patch` on the one `zot-htpasswd` `ExternalSecret` by name.

## Testing

Run `make check` to validate the chart manifests and test fixtures via
Helm template rendering against `yq` + `jq` assertions, plus
`bootstrap-script.bats`'s direct (mocked) exercise of `zot-bootstrap`'s
script logic.
