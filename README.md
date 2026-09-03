# k8s-zot

[Zot](https://zotregistry.dev/) — self-hosted OCI registry for pulling and
pushing container images.

## Credentials

Two users control access:

- **`ci`**: admin user (read/create/update/delete on all repositories).
  Used by publish workflows across the org to push new images.
- **`ci-readonly`**: read-only user (read-only access to all repositories
  via `**` wildcard). Intended for pull-only consumers — image pull secrets,
  `homelab-woodpecker`'s pull config, etc.

Passwords for both users live in OpenBao at `kv/homelab/zot` property
`HTPASSWD` (as a combined htpasswd blob). Regenerating that blob is a
manual, out-of-band step — not automated by this chart.

The `defaultPolicy: []` ensures no user gains implicit access beyond their
explicit policy. Per-repository scoping of *publish* credentials is tracked
separately (see the `mattjmorrison-homelab/.github` repo's `docs/TODO.md`,
entry "TODO: real per-repo isolation for Zot publish credentials").

## Testing

Run `make check` to validate the chart manifests and test fixtures via
Helm template rendering against `yq` + `jq` assertions.
