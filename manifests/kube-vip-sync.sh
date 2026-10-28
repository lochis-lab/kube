#!/bin/bash
# kube-vip sync — MANUAL, run on master-01 when you have DELIBERATELY decided
# to bump kube-vip (read the release notes first: this object keeps the API
# VIP alive; a bad roll = cluster unreachable). No cron on purpose.
#
# Usage: sudo /usr/local/scripts/kube-vip-sync.sh [--force]
#
# What it does: fetches manifests/kube-vip.yaml from lochis-lab/kube main,
# shows the version diff, writes it over the k3s auto-deploy manifest
# (previous copy kept as .bak), and k3s rolls the DS (maxUnavailable 1).
# --force skips the confirmation prompt.

set -euo pipefail

MANIFEST="/var/lib/rancher/k3s/server/manifests/kube-vip.yaml"
REMOTE="https://raw.githubusercontent.com/lochis-lab/kube/main/manifests/kube-vip.yaml"
TMP=$(mktemp)

cleanup() { rm -f "$TMP"; }
trap cleanup EXIT

if ! curl -m 15 -fsS "$REMOTE" -o "$TMP"; then
  echo "ERROR: could not fetch $REMOTE — no changes made." >&2
  exit 1
fi

REMOTE_VERSION=$(grep "image: ghcr.io/kube-vip/kube-vip:" "$TMP" | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" | head -n1)
LOCAL_VERSION=$(grep "image: ghcr.io/kube-vip/kube-vip:" "$MANIFEST" | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" | head -n1)
[ -n "$REMOTE_VERSION" ] && [ -n "$LOCAL_VERSION" ] || { echo "ERROR: version parse failed"; exit 1; }

if cmp -s "$TMP" "$MANIFEST"; then
  echo "In sync ($LOCAL_VERSION). Nothing to do."
  exit 0
fi

echo "Local : $LOCAL_VERSION"
echo "Repo  : $REMOTE_VERSION"
diff "$MANIFEST" "$TMP" || true

if [ "${1:-}" != "--force" ]; then
  printf "Apply repo version to %s? [y/N] " "$MANIFEST"
  read -r REPLY
  [ "$REPLY" = "y" ] || { echo "Aborted, no change."; exit 0; }
fi

cp "$MANIFEST" "$MANIFEST.bak"
cat "$TMP" > "$MANIFEST"
echo "Written (backup: $MANIFEST.bak). k3s will roll kube-vip-ds now — WATCH IT:"
echo "  kubectl -n kube-system rollout status ds/kube-vip-ds --timeout=120s"
echo "  kubectl get --raw=/readyz   # API still via the VIP"
