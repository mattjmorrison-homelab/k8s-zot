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

## Testing

Run `make check` to validate the chart manifests and test fixtures via
Helm template rendering against `yq` + `jq` assertions, plus
`bootstrap-script.bats`'s direct (mocked) exercise of `zot-bootstrap`'s
script logic.
