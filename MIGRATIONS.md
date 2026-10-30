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
| 21 | metallb v0.13.12 | controller+speaker+pool CRs | ✅ PR #111+follow-up — NOT take-ownable (raw-manifest selectors immutable vs chart): delete-and-reinstall cutover at exact 0.13.12 (~40s VIP outage, 2026-10-29), then import+state-patch. Gotchas solved: SSA conflicts on adoption → CRDs force-adopted (field-manager `helm`) + `helm.sh/resource-policy: keep` + `crds.enabled=false` (chart's static conversion caBundle conflicts with metallb controller's rotated cert on every apply at 0.13.x). All 12 VIPs + pool CRs verified. Chart bump DONE 2026-10-29 (PR #117, CRD ceremony pre-applied; frrk8s off — L2-only). Follow-ups DONE same day (PR #118): pool/L2adv CRs typed (kubernetes_manifest, imported), crds subchart back ON (0.16 has no conversion webhooks → caBundle conflict class gone; CRDs needed helm ownership labels/annotations added by hand before the chart could adopt them), renovate guard dropped — plain bumps safe again | ✅ |
| 22 | kube-vip v0.8.2 | DaemonSet (3 masters) | ✅ NOT TF (owner decision): managed as k3s auto-deploy manifest — `manifests/kube-vip.yaml` (byte-identical to master-01's file, the single source) + `kube-vip-sync.sh` MANUAL sync (no cron — deliberate, eyes-on bumps); svc_enable=false explicit; emergency runbook in plans/ | ✅ |
| 23 | ~~kube-vip-cloud-provider~~ | — | 🗑 DONE 2026-10-28: deployment was hand `kubectl apply`'d (last-applied annotation, no k3s manifest) — deleted deploy + CM + RBAC; no svc used loadBalancerClass; SyncLoadBalancerFailed spam stopped | ✅ |

## Tier 6 — storage & rancher stack (preconditions + schedule windows)
| # | App | Objects | Notes | Status |
|---|---|---|---|---|
| 24 | longhorn v1.9.2 | full system | ✅ DONE 2026-10-30 (PRs #120/#122/#123): BackupTarget → Garage S3 + restore proof (checksums identical); daily-backup RecurringJob TF-owned (07:00Z, retain 14); single-default-SC (k3s local-storage disabled on 3 masters); ADOPTED raw→helm chart 1.9.2 rev 1, all 40 chart-owned objects pre-stamped with Helm ownership, engines/replicas never restarted, 30/30 volumes healthy. Lives in terraform/longhorn (pilot per-app root module, own state+project). Known: user-created Backup CRs broken in 1.9.2 (webhook no-route) — RecurringJob is THE backup path; setting changes only via values.defaultSettings. **UPGRADE LADDER DONE same day**: k3s fleet-wide v1.33.9→v1.34.12 (all 7 nodes, config.yaml-holds-all-flags), then chart 1.9.2→1.10.2→1.11.3→1.12.1→1.13.0 with `concurrentAutomaticEngineUpgradePerNodeLimit=3` (engines self-roll; 28/28 healthy at 1.13.0, global-manager Deployment). Post-1.13 cleanup: `networkPolicies.restrictInternalTraffic=false` mitigation line removable in own PR | ✅ |
| 25 | rancher 2.14.0 | helm release | any diff restarts 3 replicas (UI/API outage); never let a plan regenerate its bootstrap/tls secrets. Fleet is idle (0 GitRepos, only fleet-agent-local) — keep-rancher-vs-shed-it is a separate owner decision (import ≠ endorsement) | ⬜ |
| 26 | rancher-webhook | helm release | import WITH rancher; apply sequence inside the tier: SUC → webhook → fleet → rancher | ⬜ |
| 27 | system-upgrade-controller | helm release | THE node-upgrade mechanism (k3s master/worker Plans) — genuinely load-bearing; never roll while a Plan is executing; running image v0.19.0 vs chart appVersion drift noted | ⬜ |
| 28 | fleet + fleet-crd | helm releases | with rancher; fleet-agent-local / rancher-turtles / CAPI stay unmanaged (chart-generated pseudo-versions, zero usage) | ⬜ |

## Tier 7 — self-import
| # | App | Objects | Notes | Status |
|---|---|---|---|---|
| 29 | atlantis 6.16.2 | helm_release | values already live in `helm/atlantis/values.yaml` (its own TODO). The apply modifies the applier: plan locally, prove No changes, single quiet-window apply, verify /healthz before any further commands. ops tfstate Secrets/Leases stay backend-owned, never TF-managed | ⬜ |
| 30 | per-app TF layout rollout | platform | Migrate the 7 remaining platform helm releases (reflector, homepage, pihole, authentik, cert-manager, traefik, metallb) into per-app root modules like terraform/longhorn/ (pilot PR #123): own backend secret kube-<app>, own atlantis project, state rm + import per app, one app per PR. End state: platform dir emptied/retired | ⬜ |

## Hygiene quick wins (tiny PRs, no imports — from the 2026-11 audit)
- ~~StorageClass: drop `local-path`'s default-class annotation~~ **DONE 2026-10-30**: local-storage provisioner disabled on all 3 masters (config.yaml `disable`), local-path SC gone entirely; `longhorn` is the sole default SC
- Delete the duplicate `paloch-web` IngressRoute in ns `traefik` (the real one lives in ns `paloch`)
- Trim reflector's allowed/auto namespace lists — `pi-omni` and `micro-transcribe` are long gone
- quickticket #13: the PV (not the PVC) is the poisoned object — marked-for-deletion PV → 10k+ FailedAttachVolume events → prod PG ContainerCreating for a month. Fix: drop the pvc-protection finalizer, let the PV finish deleting, let the deployment re-provision (old prod data already unrecoverable; PR #70 has the analysis)

## Decommission candidates (do NOT migrate)
- ~~default ns playground: lavalink, mongo, mongo-express~~ **RESOLVED 2026-11-28**: audit verdict overturned by live evidence — mongo (osu-tracker DB) + lavalink (vocard-dashboard web player, Client [WEB] in logs) were load-bearing. Both ADOPTED into TF (modules/mongo in ns default; modules/lavalink recreated in ns vocard with VIP .163 + ExternalName alias preserved). mongo-express: DELETED (crashlooped 74×, no users). Leftover: `financial-planner` DB (732K, no in-cluster owner) — VIP .160 stays until its fate is decided; `Aerosol` DB = dead data, drop when convenient
- **NAMESPACE PURGE 2026-10-30 — all deleted, zero stragglers**: `udpTest` + `micro-transcribe` (already gone before the pass), `seafile` + `valheim` (empty), `wyze-bridge` (deploy+svc, no PVC), `snap-camera` + `snap-camera-server` (secrets/CMs only; the 288d Ready=False cert IR deleted FIRST), `portainer` (stack + degenerate mongo pair + 2 LB svcs VIPs .162/.164 + 15Gi PVCs + its svclb hostPort-8000 pods — the vocard scheduling conflict source). Volumes 30→28, all healthy. NOT yet removed: `pterodactyl` ns (row 12: decommission window due since ~2026-11-03 — 70Gi of PVCs), kubero-managed ns's (kubero's problem)
- micro-transcribe + pi-omni — user confirmed 2026-11: not staying; decommission workloads when convenient — **ns already gone as of the 2026-10-30 purge**
- kube-vip-cloud-provider — see tier 5 #23
- coredns + other k3s-packaged bits (metrics-server, local-path-provisioner): hands-off forever — k3s rewrites them on every upgrade; custom DNS goes in coredns custom override files, not TF. (rancher/longhorn/kube-vip moved OUT of hands-off into tiers 5–6 per the 2026-11 audit)

## Rules (baked from the audiobookshelf incident)
1. Explicit `metadata.namespace` in every manifest.
2. Export → sanitize selectively: keep ingress.class/websocket annotations.
3. Strip clusterIP/ipFamilies from Services.
4. Single-instance RWO apps → `strategy: Recreate`.
5. `kubectl diff -R -f` (rendered) = 0 lines before deleting legacy sources.
6. One app per PR; apply via `atlantis apply -p terraform-apps`; verify route 200 after.
