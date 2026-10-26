# Bootstrap notes

- Decisions locked 2026-11: GitHub repo (public — no access details or secrets
  in this repo, ever); Terraform + Atlantis as the applier; scope split
  (platform = Terraform, apps = raw YAML).
- Phase order: 0 repo → 0.5 manifest consolidation → 1 TF state backend →
  2 Atlantis → 3 Renovate + k3s upgrade plans → 4 platform imports →
  5 optional (proxmox provider, fleet handoff).
- Operational runbook (cluster access, jump hosts) is kept off-repo.

## Placeholders
- `NFS_MEDIA_SERVER` in apps/audiobookshelf — LAN NFS host for /srv/audiobooks +
  /srv/podcasts. Real value lives in cluster only (already applied); replace in a
  local uncommitted copy or via `envsubst` when re-applying. Do NOT commit it.
