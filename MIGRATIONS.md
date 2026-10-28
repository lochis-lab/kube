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
| 15 | homepage | simple chart, config via CM — 🚧 PR #73: imported `homepage` chart 4.2.0 (OCI `ghcr.io/m0nsterrr/helm-charts`); live release has no CM yet, config is chart/env-side only | 🚧 |
| 16 | pihole | CLUSTER DNS — apply from inside cluster, verify resolution immediately | ✅ PR #82 — imported (state-push patch: repository + values), plan No changes, dig/svc/pod verified, rev 1 untouched | ✅ |
| 17 | cert-manager | cert issuance for all routes; import at exact chart version | ✅ PR #83 — imported (state-push patch: repository + values), plan No changes, 3×controller+cainjector+webhook untouched, certs renewing | ✅ |
| 18 | authentik | chart + its postgres STS + CRDs; import at exact chart version | ✅ PR #84 — creds → atlantis-app-vars (TF_VAR pattern), atlantis helm upgraded w/ env wiring (chart repo moved to runatlantis.github.io/helm-charts), imported + state-patch + one no-op apply to record sensitive-values marking; plan No changes, pods untouched | ✅ |
| 19 | traefik | LAST — carries every route incl. Atlantis's own webhook path | ✅ PR #85 — imported (state-push patch: repository + values), plan No changes, pods/routes/atlantis untouched | ✅ |

## Tier 5 — leftover apps & load balancing (from the 2026-11 cluster audit)
| # | App | Objects | Notes | Status |
|---|---|---|---|---|
| 20 | jackett | deploy+svc+PVC+IR | 🗑 KILLED 2026-10-28 (owner decision: not feeding ABS — no *arr apps exist, no references in ABS config): deploy+svc+IR+2Gi longhorn PVC deleted from audiobookshelf ns | ✅ |
| 21 | metallb v0.13.12 | controller+speaker+pool CRs | the ONLY working LB IPAM (kube-vip is CP-VIP-only). Raw manifests, NO helm release → adopt via `helm upgrade --install --take-ownership`, then `terraform import helm_release`; IPAddressPool/L2Advertisement stay typed so allocation policy is reviewable. Upgrade = CRD swap (v1beta1, deprecation warnings already), NOT a values bump. Blast radius = all 15 LB svcs (speaker restart = ARP blip on every LB addr); preserve pihole's allow-shared-ip annotation | ⬜ |
| 22 | kube-vip v0.8.2 | DaemonSet (3 masters) | control-plane VIP only — keep `svc_enable=false` explicit in values or we grow a third LB implementation. Adopt+import; no-diff import ONLY, never combined with a version bump; owns the API VIP, a bad apply = cluster unreachable | ⬜ |
| 23 | ~~kube-vip-cloud-provider~~ | — | 🗑 DONE 2026-10-28: deployment was hand `kubectl apply`'d (last-applied annotation, no k3s manifest) — deleted deploy + CM + RBAC; no svc used loadBalancerClass; SyncLoadBalancerFailed spam stopped | ✅ |

## Tier 6 — storage & rancher stack (preconditions + schedule windows)
| # | App | Objects | Notes | Status |
|---|---|---|---|---|
| 24 | longhorn v1.9.2 | full system | BLOCKED until a backup target is configured AND one restore proven (owns 35/35 PVCs; zero restore path today — backuptarget empty, snapshots not readyToUse). Adopt via `--take-ownership` chart, never typed (CSI + webhooks + 40+ CRDs). Fix the two-default-StorageClasses bug in its own PR first; upgrades ride longhorn's own engine-drain path — TF must not force manager restarts | ⬜ |
| 25 | rancher 2.14.0 | helm release | any diff restarts 3 replicas (UI/API outage); never let a plan regenerate its bootstrap/tls secrets. Fleet is idle (0 GitRepos, only fleet-agent-local) — keep-rancher-vs-shed-it is a separate owner decision (import ≠ endorsement) | ⬜ |
| 26 | rancher-webhook | helm release | import WITH rancher; apply sequence inside the tier: SUC → webhook → fleet → rancher | ⬜ |
| 27 | system-upgrade-controller | helm release | THE node-upgrade mechanism (k3s master/worker Plans) — genuinely load-bearing; never roll while a Plan is executing; running image v0.19.0 vs chart appVersion drift noted | ⬜ |
| 28 | fleet + fleet-crd | helm releases | with rancher; fleet-agent-local / rancher-turtles / CAPI stay unmanaged (chart-generated pseudo-versions, zero usage) | ⬜ |

## Tier 7 — self-import
| # | App | Objects | Notes | Status |
|---|---|---|---|---|
| 29 | atlantis 6.16.2 | helm_release | values already live in `helm/atlantis/values.yaml` (its own TODO). The apply modifies the applier: plan locally, prove No changes, single quiet-window apply, verify /healthz before any further commands. ops tfstate Secrets/Leases stay backend-owned, never TF-managed | ⬜ |

## Hygiene quick wins (tiny PRs, no imports — from the 2026-11 audit)
- StorageClass: drop `local-path`'s default-class annotation (two default SCs = latent scheduling trap)
- Delete the duplicate `paloch-web` IngressRoute in ns `traefik` (the real one lives in ns `paloch`)
- Trim reflector's allowed/auto namespace lists — `pi-omni` and `micro-transcribe` are long gone
- quickticket #13: the PV (not the PVC) is the poisoned object — marked-for-deletion PV → 10k+ FailedAttachVolume events → prod PG ContainerCreating for a month. Fix: drop the pvc-protection finalizer, let the PV finish deleting, let the deployment re-provision (old prod data already unrecoverable; PR #70 has the analysis)

## Decommission candidates (do NOT migrate)
- default ns playground: lavalink, mongo, mongo-express
- udpTest (test junk) · valheim/ (manifests exist, nothing deployed)
- micro-transcribe + pi-omni — user confirmed 2026-11: not staying; decommission workloads when convenient
- wyze-bridge — user confirmed 2026-10-27: moved from Tier 2 #9; do NOT migrate, decommission when convenient
- portainer — overlaps Atlantis; decommission after tier 4 stabilizes (3 LB svcs + mongo duplicate + 16Gi PVCs still held; it is also the origin of most unmanaged objects above — migrate/delete those first so its stack records aren't the only provenance)
- kubero-managed apps (aerosol, rockywestprod) stay kubero's problem
- snap-camera + snap-camera-server — nothing deployed, but an IR still publishes a third-party host with a cert Ready=False for 282d: kill the IR first (only live exposure), then the namespaces
- ns `aerosol` orphan bits — LB svc with NO endpoints, an IR for it, and stray secrets/tls; the real app lives in kubero's aerosol-production
- empty namespaces: `seafile`, `valheim` (nothing but kube-root-ca.crt)
- orphan PVCs (~14Gi): `audiobookshelf/audiobookshelf-config` + `audiobookshelf-metadata` (superseded by abs-*), `default/vocard-pvc`, `portainer/vocard-pvc`; plus orphaned vocard CMs/Secret in `default`
- duplicate mongo pair in ns `portainer` (portainer stack 345 — degenerate copy of the default-ns playground stack)
- kube-vip-cloud-provider — see tier 5 #23
- coredns + other k3s-packaged bits (metrics-server, local-path-provisioner): hands-off forever — k3s rewrites them on every upgrade; custom DNS goes in coredns custom override files, not TF. (rancher/longhorn/kube-vip moved OUT of hands-off into tiers 5–6 per the 2026-11 audit)

## Rules (baked from the audiobookshelf incident)
1. Explicit `metadata.namespace` in every manifest.
2. Export → sanitize selectively: keep ingress.class/websocket annotations.
3. Strip clusterIP/ipFamilies from Services.
4. Single-instance RWO apps → `strategy: Recreate`.
5. `kubectl diff -R -f` (rendered) = 0 lines before deleting legacy sources.
6. One app per PR; apply via `atlantis apply -p terraform-apps`; verify route 200 after.
