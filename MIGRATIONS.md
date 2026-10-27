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
| 11 | headscale | deploy+PVC+IR | TAILNET CONTROL PLANE — a bad apply cuts remote access; pin console `:latest`; re-test plan on a copied manifest first | ⬜ |
| 12 | pterodactyl | 3 deploys+2 PVC | game panel; check hostPort/networking | ⬜ |
| 13 | quickticket | 4 deploys+4 PVC+secrets | dev+prod PG/redis pairs | ⬜ |

## Tier 4 — platform helm imports (terraform/platform, helm_release imports)
| # | Release | Why this order | Status |
|---|---|---|---|
| 14 | reflector | single deploy, nothing depends on it at apply time | ⬜ |
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
