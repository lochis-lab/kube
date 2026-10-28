# Migration backlog — easiest → hardest, one app per PR

Status key: ⬜ todo · 🚧 in progress · ✅ done · 🗑 decommission instead

## Tier 1 — warm-ups (single deployment, manifests exist, low blast radius)
| # | App | Objects | Notes | Status |
|---|---|---|---|---|
| 0 | audiobookshelf | 8 | pilot; namespace+annotations+Recreate lessons baked in | ✅ |
| 1 | searxng | ns+CM+deploy+svc | ✅ migrated via PR #15 — secrets extracted to atlantis-app-vars, digest-pinned | ✅ |
| 2 | dealchis | deploy only | ✅ PR #25 — svc/IR no longer existed; creds stay in unmanaged k8s Secret | ✅ |
| 3 | osu-tracker | deploy+IR+cronjob | ✅ PR #27 — secrets extracted to atlantis-app-vars; cronjob as manifest (typed cron_job forces replacement); portainer SSA fields taken via kubectl force-apply + field_manager.force_conflicts | ✅ |

## Tier 2 — real state, still simple shapes
| # | App | Objects | Notes | Status |
|---|---|---|---|---|
| 5 | homeassistant | deploy+PVC+IR | ✅ PR #30 — USB-passthrough pre-check: none exists (plain PVC shape); Recreate kept; PVC 10Gi longhorn | ✅ |
| 6 | cloudreve | 3 deploys+2 PVC | ✅ PR #37+#40 — app digest-pinned (sha256:5c6c5baf…); cloudreve-config Secret unmanaged; Recreate strategy on pg/redis (RWO Multi-Attach trap); redis requirepass command restored from old RS after 500 incident; DB majors config-pinned (#41) | ✅ |
| 7 | n8n | deploy+pg STS+PVC | ✅ this PR — app digest-pinned (sha256:d02752c6…); n8n-secret + postgres-secret unmanaged (secretKeyRef only); pg 16 major-pinned; headless svc preserved | ✅ |
| 8 | firecrawl | 6 deploys+2 PVC | ✅ PR #32 — firecrawl-secret stays unmanaged (envFrom/secretKeyRef); worker drain windows + playwright securityContext preserved; scrape-verified end-to-end | ✅ |
| 10 | batch: vocard, paloch, omniroute, auto-school | mixed | ✅ PRs #55/#56/#57/#58 — 4 tiny PRs done; vocard dashboard inline secrets → unmanaged Secret; omniroute tailscale sidecar automount fix (2/2 Running); pgvector added to major-pin rule | ✅ |

## Tier 3 — critical infra & multi-env (schedule windows)
| # | App | Objects | Notes | Status |
|---|---|---|---|---|
| 11 | headscale | deploy+PVC+IR | ✅ PR #60 — 10 objs (ns,deploy,svc,PVC,2×CM,3×IR,IRTCP-gRPC-passthrough); RollingUpdate→Recreate (RWO multi-attach); console :latest→digest; portainer labels off IRTCP; all tailnet nodes re-online after apply. Pre-existing console 404 (controlUrl :2459 vs IR :443 mismatch) NOT fallout | ✅ |
| 12 | ~~pterodactyl~~ → **pelican** | new ns+db+panel (side-by-side) | ✅ PR #67+#69 — Pelican panel + wings live since 2026-10-27 on a cloned DB (own MariaDB 10.11). Backups verified end-to-end (host↔node mapping + per-server file layout, see `docs/pelican-cutover.md` §7.7). Pterodactyl ns kept for rollback; decommission after ~1 week. | ✅ |
| 13 | quickticket | 4 deploys+4 PVC+secrets | 🚧 PR #70 — **INCIDENT 2026-10-28**: a main-based `terraform-apps` apply (#69) destroyed the imported objects + the whole ns (trap: out-of-band imports in shared state + apply from a branch lacking the module = destroys; dev DB/redis data lost, prod data was already unrecoverable). Resolution IN this PR: module is now pure create-from-scratch — ns + dev PG + dev/prod redis + **fresh prod PG (10Gi)**, no imports, no manual PV surgery | 🚧 |

## Tier 4 — platform helm imports (terraform/platform, helm_release imports)
| # | Release | Why this order | Status |
|---|---|---|---|
| 14 | reflector | single deploy, nothing depends on it at apply time | 🚧 PR #71 |
| 15 | homepage | simple chart, config via CM | ⬜ |
| 16 | pihole | CLUSTER DNS — apply from inside cluster, verify resolution immediately | ⬜ |
| 17 | cert-manager | cert issuance for all routes; import at exact chart version | ⬜ |
| 18 | authentik | chart + its postgres STS + CRDs; import at exact chart version | ⬜ |
| 19 | traefik | LAST — carries every route incl. Atlantis's own webhook path | ⬜ |

## Decommission candidates (do NOT migrate)
- default ns playground: lavalink, mongo, mongo-express
- udpTest (test junk) · valheim/ (manifests exist, nothing deployed)
- micro-transcribe + pi-omni — user confirmed 2026-11: not staying; decommission workloads when convenient
- wyze-bridge — user confirmed 2026-10-27: moved from Tier 2 #9; do NOT migrate, decommission when convenient
- portainer — overlaps Atlantis; decommission after tier 4 stabilizes
- kubero-managed apps (aerosol, rockywestprod) stay kubero's problem
- rancher stack / longhorn / kube-vip / coredns: hands-off forever (own upgrade paths)

## Rules (baked from the audiobookshelf incident)
1. Explicit `metadata.namespace` in every manifest.
2. Export → sanitize selectively: keep ingress.class/websocket annotations.
3. Strip clusterIP/ipFamilies from Services.
4. Single-instance RWO apps → `strategy: Recreate`.
5. `kubectl diff -R -f` (rendered) = 0 lines before deleting legacy sources.
6. One app per PR; apply via `atlantis apply -p terraform-apps`; verify route 200 after.
