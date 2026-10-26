# Bootstrap notes
- Cluster access: ssh root@100.64.0.3 (dell-pve-1) → ssh lochis@192.168.10.137 (k3s-admin); kubectl works as lochis.
- Decisions locked 2026-11: github.com private repo; TF+Atlantis applier; scope split (platform=TF, apps=raw YAML).
- Phase order: 0 repo → 0.5 manifest consolidation → 1 TF backend (MinIO) → 2 Atlantis → 3 Renovate + k3s upgrade plans → 4 platform imports → 5 optional (proxmox, fleet).
