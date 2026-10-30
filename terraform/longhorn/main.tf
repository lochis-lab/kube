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
  version    = "1.12.1"
  # Engine auto-upgrade: without this (default 0) engines stay on old binaries
  # after chart bumps (all 30 were still v1.9.2 after the 1.10.2→1.11.3 hops).
  # 3 concurrent live engine upgrades per node; volumes are RF2.
  values = [yamlencode({
    defaultSettings = {
      concurrentAutomaticEngineUpgradePerNodeLimit = 3
    }
    # 1.12.1 mitigation for longhorn#13804: default-on netpol misses
    # host-originated CSI calls (kubelet attach/detach) — volumes silently
    # fail to mount. Fixed upstream in 1.12.2; revisit then.
    networkPolicies = {
      restrictInternalTraffic = false
    }

  })]
}

# Backup target — Garage S3 (bucket "longhorn") served from a pve1 LXC.
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
