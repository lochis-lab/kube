# longhorn — pilot of the per-app root-module layout (2026-10-30), moved from
# terraform/platform. Own state (kube-longhorn), own atlantis project: plans and
# applies here can never touch another app's resources.
#
# Adoption note: this directory ADOPTS the live raw-manifest longhorn v1.9.2
# (deploy/longhorn.yaml) — see helm_release.longhorn below.

resource "helm_release" "longhorn" {
  name       = "longhorn"
  namespace  = "longhorn-system"
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = "1.9.2" # app v1.9.2 — ADOPTION 2026-10-30: live raw-manifest install
  # (deploy/longhorn.yaml v1.9.2) brought under helm without reinstall:
  # all 40 chart-owned live objects (22 CRDs, manager DaemonSet, ui +
  # driver-deployer Deployments, SAs/RBAC/Services/ConfigMaps/PriorityClass)
  # were pre-stamped app.kubernetes.io/managed-by=Helm + meta.helm.sh/release-*
  # so helm adopts them in place — zero pod restarts (verified: images/replicas
  # identical chart-vs-live, CSI components stay deployer-owned, not chart-owned).
  # Values intentionally EMPTY: settings live in Setting CRs the chart doesn't
  # own; any future setting change must go through values.defaultSettings (a
  # kubectl edit would be reverted by the next manager start). BackupTarget/
  # RecurringJob are separately TF-owned kubernetes_manifests below. Upgrade
  # path: chart bump PRs; engine upgrades ride longhorn's own engine-drain —
  # TF must never force manager/engine restarts (no atomic, no wait timeouts).
  values = []
}

# Backup target — Garage S3 (bucket "longhorn") served from a pve1 LXC.
# Longhorn 1.9 configures targets via the BackupTarget CR (the old settings
# backup-target / backup-target-credential-secret are gone); "default" existed
# empty since install and was IMPORTED, not created. Credentials live in the
# Secret below, values via TF_VARs from atlantis-app-vars (LONGHORN_BACKUP_*);
# the endpoint URL is an infra detail and never appears in this repo.
# Restore proof passed 2026-10-29 (backup → volume destroyed → restored,
# checksums identical) — MIGRATIONS.md #24 gate evidence.
resource "kubernetes_manifest" "longhorn_backuptarget" {
  field_manager {
    force_conflicts = true # longhorn-manager owns the seeded empty defaults
  }
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "BackupTarget"
    metadata = {
      name      = "default"
      namespace = "longhorn-system"
    }
    spec = {
      backupTargetURL  = "s3://longhorn@garage/"
      credentialSecret = kubernetes_secret_v1.longhorn_backup.metadata[0].name
    }
  }
}

resource "kubernetes_secret_v1" "longhorn_backup" {
  metadata {
    name      = "longhorn-backup"
    namespace = "longhorn-system"
  }

  data = {
    AWS_ACCESS_KEY_ID     = var.longhorn_backup_access_key
    AWS_SECRET_ACCESS_KEY = var.longhorn_backup_secret_key
    AWS_ENDPOINTS         = var.longhorn_backup_endpoint
  }
}

# Daily backup — the ONLY working backup path in 1.9.2: user-created Backup
# CRs die in the admission webhook (no-route bug), manager/recurring-job-
# created backups are fine (proven: full-cluster kickoff + restore proof,
# 2026-10-29, see MIGRATIONS.md #24). Group "default" is stamped on every
# volume by the longhorn mutator, so this covers all attached volumes;
# detached orphans are skipped by design. Cron is UTC — 07:00Z = 02:00
# America/Toronto in winter (EST), 03:00 during DST.
resource "kubernetes_manifest" "longhorn_recurringjob_daily_backup" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"
    metadata = {
      name      = "daily-backup"
      namespace = "longhorn-system"
    }
    spec = {
      name        = "daily-backup" # must match metadata.name
      cron        = "0 7 * * *"
      task        = "backup"
      retain      = 14
      concurrency = 1
      groups      = ["default"]
    }
  }
}
