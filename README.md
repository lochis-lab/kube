# lochis-lab/kube

GitOps source of truth for the homelab k3s cluster.

## Layout
- `apps/` — per-app raw manifests (applied via Atlantis custom workflow)
- `terraform/infra/` — Terraform state backend (kubernetes backend: Secret+Lease in ns `ops`), namespaces, Atlantis itself
- `terraform/platform/` — platform helm releases (reflector, homepage, pihole, cert-manager, authentik, traefik — import order = risk-ascending)
- `plans/` — system-upgrade-controller plans (k3s version pinned here; Renovate bumps it)
- `docs/` — runbooks (operational access details live off-repo)

## Migration status
| App | In repo | Promoted (applied from repo) |
|---|---|---|
| audiobookshelf | ✅ | ⬜ pending Atlantis |

## Rules
- One app per PR; plan/diff must be clean before deleting legacy sources.
- Never `kubectl edit` anything promoted — PR only.
- Secrets live in the cluster's Secret store — never in this repo.
