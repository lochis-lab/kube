# lochis-lab/kube

GitOps source of truth for the homelab k3s cluster. **Everything is Terraform** —
platform and apps alike. PRs are planned/applied by
[Atlantis](https://www.runatlantis.io), version bumps arrive as PRs from
[Renovate](https://renovatebot.com).

## How it works

```
Renovate PR (image/provider bump)          you push a PR
        │                                        │
        ▼                                        ▼
   GitHub ── webhook ──► Atlantis (in cluster, ns ops)
                             │ terraform plan (auto)
                             ▼
                     PR comment shows the diff
                             │ you comment: atlantis apply -p <project>
                             ▼
                      terraform apply to k3s
```

- **Repos of record**: `terraform/infra`, `terraform/platform`,
  `terraform/apps` are three Atlantis projects — a PR plans only the scope it
  touches, and each has its own state Secret (`tfstate-default-kube-*` in ns
  `ops`, kubernetes backend with Lease locking; backups ride k3s etcd
  snapshots).
- **Atlantis** is installed via the official helm chart (`helm/atlantis/`).
  Terraform is runtime-downloaded into the pod; `kubectl` comes from an
  initContainer. Config: repo-root `atlantis.yaml`.

## Layout

- `terraform/apps/` — all applications, **pure typed HCL** (no YAML, no
  templates):
  - `namespaces.tf` — every app namespace in one place
  - `main.tf` — module wiring
  - `modules/<app>/` — `kubernetes_deployment_v1`, `kubernetes_service_v1`,
    `kubernetes_persistent_volume_claim_v1`, `kubernetes_config_map_v1`, …;
    `kubernetes_manifest` (inline HCL) only for CRDs like Traefik
    IngressRoutes
- `terraform/infra/` — state backend, namespaces, Atlantis itself
- `terraform/platform/` — platform helm releases (reflector → homepage →
  pihole → cert-manager → authentik → traefik, import order = risk-ascending)
- `plans/` — system-upgrade-controller plans (k3s version pinned; Renovate
  bumps it)
- `helm/atlantis/` — Atlantis chart values
- `docs/` — runbooks (operational access details live off-repo)

## Secrets

Never in this repo. Sensitive values (NFS host, searxng secret key, proxy
creds, …) live in the in-cluster Secret `atlantis-app-vars` (ns `ops`) and are
injected as `TF_VAR_*` into the Atlantis pod via the chart's
`environmentSecrets`. They are declared `sensitive` in
`terraform/apps/variables.tf`, so plans redact them automatically.

## Migrations

~20 legacy apps are moving in from hand-managed manifests, one PR each.
See [MIGRATIONS.md](MIGRATIONS.md) for the backlog and the per-app recipe:

> write `modules/<app>/` → add namespace to `namespaces.tf` →
> `terraform import` (module-scoped addresses) → plan must be a no-op → PR.

## Rules

- One app per PR; plan must be clean before deleting legacy sources.
- Never `kubectl edit` anything promoted — PR only.
- Secrets live in the cluster's Secret store — never in this repo.
- This repo is public: no IPs, hostnames-as-access-info, or SSH chains.
  Runbooks stay off-repo.

## Renovate

Hosted Renovate app. Managers: `terraform` (providers), `helm-values`
(Atlantis chart), `regex` for `image = "..."` in `terraform/apps/**/*.tf`
(tag and digest pins), plus the system-upgrade plan. Own
`ghcr.io/lochis/*` images are excluded.
