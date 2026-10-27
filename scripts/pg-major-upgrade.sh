#!/usr/bin/env bash
# Semi-automatic Postgres major upgrade for TF-managed single-instance dbs.
#
#   scripts/pg-major-upgrade.sh <namespace> <from-major> <to-major> [secret]
#
# What it does (idempotent per step, stops on first failure):
#   1. pg_dump  the live postgres deployment            -> backups/
#   2. create   postgres-data-v<to> PVC (size/class copied from the live PVC)
#   3. run a throwaway postgres:<to> pod on the new PVC (initdb via the same
#      secret-sourced POSTGRES_* env as the deployment)
#   4. restore the dump into it, sanity-check relations
#   5. print the EXACT terraform edits + PR/apply/cleanup checklist
#
# You then: commit the printed HCL edits -> PR -> `atlantis apply` -> verify
# the app -> cleanup (printed last) removes the old deployment PVC.
#
# The throwaway pod is deleted before you apply, so the new PVC is free for
# the TF-managed deployment to attach (RWO).
set -euo pipefail

NS=${1:?usage: pg-major-upgrade.sh <namespace> <from-major> <to-major> [secret]}
FROM=${2:?from-major, e.g. 15}
TO=${3:?to-major, e.g. 18}
SECRET=${4:-cloudreve-config}
DEPLOY=postgres
OLD_PVC=postgres-data
NEW_PVC=postgres-data-v${TO}
TMP_POD=pg-migrate-${TO}
BK=backups/${NS}-pg${FROM}-$(date +%Y%m%d-%H%M%S).sql
KG=backups/${NS}-pg${FROM}-$(date +%Y%m%d-%H%M%S)-globals.sql
mkdir -p backups

step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }

preflight() {
  step "preflight"
  command -v kubectl >/dev/null || { echo "kubectl not on PATH"; exit 1; }
  kubectl -n "$NS" get deploy/"$DEPLOY" >/dev/null || { echo "no deploy/$DEPLOY in $NS"; exit 1; }
  if kubectl -n "$NS" get pvc "$NEW_PVC" >/dev/null 2>&1; then
    echo "$NEW_PVC already exists — delete it first if this is a re-run after a failed restore."; exit 1; fi
  note "live PVC spec: $(kubectl -n "$NS" get pvc "$OLD_PVC" -o jsonpath='{.spec.resources.requests.storage} {.spec.storageClassName}')"
  note "Longhorn snapshot of $OLD_PVC is your rollback — do it now if you want it."
}

dump() {
  step "1/5 dump from live pg${FROM}"
  kubectl -n "$NS" exec deploy/"$DEPLOY" -- sh -c \
    'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$BK"
  kubectl -n "$NS" exec deploy/"$DEPLOY" -- sh -c \
    'pg_dumpall -U "$POSTGRES_USER" --globals-only' > "$KG" || true
  note "$(wc -l < "$BK") lines -> $BK"
  [ -s "$BK" ] || { echo "dump empty, aborting"; exit 1; }
}

new_pvc() {
  step "2/5 create $NEW_PVC"
  local SIZE CLASS
  SIZE=$(kubectl -n "$NS" get pvc "$OLD_PVC" -o jsonpath='{.spec.resources.requests.storage}')
  CLASS=$(kubectl -n "$NS" get pvc "$OLD_PVC" -o jsonpath='{.spec.storageClassName}')
  kubectl -n "$NS" apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: $NEW_PVC, namespace: $NS}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: $CLASS
  resources: {requests: {storage: $SIZE}}
EOF
}

migrate_pod() {
  step "3/5 throwaway pg${TO} pod on $NEW_PVC (initdb)"
  kubectl -n "$NS" run "$TMP_POD" --image="docker.io/library/postgres:${TO}-alpine" \
    --overrides="$(cat <<EOF
{"apiVersion":"v1","spec":{
  "containers":[{"name":"$TMP_POD","image":"docker.io/library/postgres:${TO}-alpine",
    "env":[
      {"name":"POSTGRES_DB","valueFrom":{"secretKeyRef":{"name":"$SECRET","key":"DB_NAME"}}},
      {"name":"POSTGRES_USER","valueFrom":{"secretKeyRef":{"name":"$SECRET","key":"DB_USER"}}},
      {"name":"POSTGRES_PASSWORD","valueFrom":{"secretKeyRef":{"name":"$SECRET","key":"DB_PASSWORD"}}},
      {"name":"PGDATA","value":"/var/lib/postgresql/data/pgdata"}],
    "volumeMounts":[{"name":"data","mountPath":"/var/lib/postgresql/data"}]}],
  "volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"$NEW_PVC"}}]}}
EOF
)"
  note "waiting for initdb..."
  kubectl -n "$NS" wait --for=condition=Ready "pod/$TMP_POD" --timeout=300s
  # Ready != listening: the image's initdb runs after container start.
  for i in $(seq 1 60); do
    kubectl -n "$NS" exec "$TMP_POD" -- sh -c 'pg_isready -U "$POSTGRES_USER" -q' 2>/dev/null \
      && { note "pg${TO} accepting connections"; return 0; }
    sleep 2
  done
  echo "pg${TO} never became ready"; exit 1
}

restore() {
  step "4/5 restore dump into pg${TO}"
  kubectl -n "$NS" exec -i "$TMP_POD" -- sh -c \
    'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' < "$BK"
  note "sanity: table counts"
  kubectl -n "$NS" exec "$TMP_POD" -- sh -c \
    'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "select count(*) from pg_stat_user_tables;"'
}

finish() {
  step "5/5 hand-off — do these now"
  kubectl -n "$NS" delete pod "$TMP_POD" >/dev/null && note "deleted $TMP_POD (frees the RWO PVC)"
  cat <<EOF

TF EDITS — migration PR (commit, PR, atlantis apply):
  1. terraform/apps/modules/<app>/main.tf, postgres deployment:
       image  "docker.io/library/postgres:${FROM}-alpine"
       ->     "docker.io/library/postgres:${TO}-alpine"
  2. ADD a new PVC resource postgres_data_v${TO} (name ${NEW_PVC}, same
     size/class as printed in preflight) — do NOT remove the old one yet!
     Repoint the deployment's claim_name to it.
     Removing the old PVC resource in this PR would make the apply DELETE
     ${OLD_PVC} — killing the revert-PR rollback. Old PVC stays until cleanup.
  3. adopt the pre-created PVC so TF doesn't fight the live object:
       terraform import module.<app>.kubernetes_persistent_volume_claim_v1.\
         postgres_data_v${TO} ${NS}/${NEW_PVC}

AFTER atlantis apply + app verified working — cleanup PR:
  - remove the old postgres_data PVC resource from HCL (state rm first if
    you want the PVC to survive; plain delete = kubectl deletes it):
      kubectl -n $NS delete pvc $OLD_PVC   # Longhorn-snapshot first!
      terraform state rm module.<app>.kubernetes_persistent_volume_claim_v1.postgres_data

Rollback (before the cleanup PR): revert the migration PR + atlantis apply —
old deployment + ${OLD_PVC} were never touched.
EOF
}

preflight; dump; new_pvc; migrate_pod; restore; finish
