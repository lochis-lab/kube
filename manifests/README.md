# manifests/ — k3s auto-deploy files (NOT Terraform)

## kube-vip (control-plane VIP holder)

kube-vip is deliberately **not** Terraform-managed (owner decision 2026-10-28; see
`plans/kube-vip-import-plan.md`). It runs via k3s's built-in auto-deploy mechanism:

- `kube-vip.yaml` here is **byte-identical** to
  `/var/lib/rancher/k3s/server/manifests/kube-vip.yaml` on **master-01 (192.168.10.138)** —
  the ONLY master that carries it (verified: .142 has no copy). k3s watches that dir and
  keeps the DaemonSet applied cluster-wide; deleting the DS is self-healed from the file.
- The live objects are DS `kube-vip-ds` (v0.8.2, 3 masters, hostNetwork, leader election on
  `plndr-cp-lock`) + SA `kube-vip` + ClusterRoleBinding `system:kube-vip-binding` (RBAC
  applied out-of-band; it predates this file and never changes).
- `svc_enable: "false"` is explicit — kube-vip stays control-plane-only and must NEVER
  grow service LB duties (MetalLB owns that).

## Version bumps — DELIBERATE, no cron

kube-vip holds the API VIP; a bad roll = cluster unreachable. So bumps are always a
human-in-the-loop, eyes-on-rollout event (and rare: v0.8.2 since Oct 2025):

1. Read kube-vip release notes; edit `image:` in this file; PR; merge
2. On master-01: `sudo /usr/local/scripts/kube-vip-sync.sh`
   — shows the diff, asks for confirmation, keeps a `.bak`, then k3s rolls the DS
   (maxUnavailable 1; leader election moves the VIP for ~seconds)
3. Watch it: `kubectl -n kube-system rollout status ds/kube-vip-ds` + `kubectl get --raw=/readyz`
4. If it goes wrong: `sudo cp $MANIFEST.bak $MANIFEST` rolls back the file → k3s re-rolls

One-time setup on master-01 (as lochis, passwordless sudo):
```
sudo mkdir -p /usr/local/scripts
sudo tee /usr/local/scripts/kube-vip-sync.sh < kube/manifests/kube-vip-sync.sh
sudo chmod +x /usr/local/scripts/kube-vip-sync.sh
```
(No crontab entry — that is the point.)

## Emergency (VIP dead, kubectl times out)

`ssh lochis@192.168.10.138` (or .139/.142), then against a master directly:
```
sudo kubectl --server=https://192.168.10.138:6443 apply -f <this file from any clone>
```
Full runbook: `plans/kube-vip-import-plan.md` § Emergency.
