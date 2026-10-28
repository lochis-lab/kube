#!/bin/bash
# kube-vip sync — patches the k3s auto-deploy manifest on THIS master when the
# version in lochis-lab/kube changes. Deploy on master-01 ONLY (the single
# manifest source); k3s watches the manifests dir and rolls the DaemonSet.
# Cron (root):  */30 * * * * /usr/local/scripts/kube-vip-sync.sh

LOG_FILE="/usr/local/scripts/kube-vip-sync.log"
MANIFEST="/var/lib/rancher/k3s/server/manifests/kube-vip.yaml"
REMOTE="https://raw.githubusercontent.com/lochis-lab/kube/main/manifests/kube-vip.yaml"

echo "-----" >> "$LOG_FILE"
echo "$(date) kube-vip sync starting" >> "$LOG_FILE"

REMOTE_VERSION=$(curl -m 10 -s "$REMOTE" | grep "image: ghcr.io/kube-vip/kube-vip:" | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" | head -n1)
LOCAL_VERSION=$(grep "image: ghcr.io/kube-vip/kube-vip:" "$MANIFEST" 2>/dev/null | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" | head -n1)

echo "Remote: $REMOTE_VERSION" >> "$LOG_FILE"
echo "Local : $LOCAL_VERSION" >> "$LOG_FILE"

if [ -z "$REMOTE_VERSION" ] || [ -z "$LOCAL_VERSION" ]; then
  echo "ERROR: missing version (repo unreachable or local manifest gone) — no change made" >> "$LOG_FILE"
  exit 0
fi

if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
  echo "UPDATE: $LOCAL_VERSION → $REMOTE_VERSION" >> "$LOG_FILE"
  sed -i "s/$LOCAL_VERSION/$REMOTE_VERSION/g" "$MANIFEST"
  # k3s picks up the file change automatically and rolls the DS (maxUnavailable 1)
else
  echo "No change" >> "$LOG_FILE"
fi
