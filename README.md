# lochis-lab/kube

GitOps source of truth for the k3s homelab. Plan of record: `PLAN.md` (kept in
~/Projects/iac-homelab on the lochis desktop; summary below).

## Layout
- `apps/` — per-namespace raw manifests (applied via Atlantis custom workflow; migrated to Terraform lazily)
- `terraform/infra/` — state backend (MinIO), namespaces, Atlantis itself
- `terraform/platform/` — helm releases: reflector, homepage, pihole, cert-manager, authentik, traefik (import order = risk-ascending)
- `plans/` — system-upgrade-controller plans (k3s version pinned here; Renovate bumps)
- `docs/` — BOOTSTRAP.md, runbooks

## Migration status
| App | In repo | Promoted (applied from repo) |
|---|---|---|
| audiobookshelf | ✅ | ⬜ pending Atlantis |

## Rules
- One app per PR; `plan`/`diff` must be clean before deleting legacy sources.
- Never `kubectl edit` anything already promoted — PR only.
- Secrets stay in k8s Secrets; never commit them.

Hands-off (their own upgrade paths): rancher, rancher-webhook, turtles, fleet,
longhorn, kube-vip, coredns, kubero-operator, portainer.
