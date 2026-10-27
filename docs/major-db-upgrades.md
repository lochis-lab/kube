# Major db upgrades (stateful singletons)

Renovate majors for `library/postgres|mongo|mariadb|mysql` are **disabled** in
`renovate.json5` — a major against a live PVC is a data migration, never a tag
swap (pg18 refuses a pg15 `PGDATA` and crash-loops). **Redis is exempt**: RDB
format is major-compatible, so redis majors flow as normal Renovate PRs
(bump → Recreate restart → `dump.rdb` loads). Snapshot the PVC before applying
a redis major anyway.

## How you find out a major exists

`.github/workflows/db-major-watch.yml` runs weekly (Sunday 09:00 Toronto), compares
the lowest pinned major per db image in `terraform/apps/modules/**.tf` against
Docker Hub's newest `-alpine` major, and opens an issue with the exact migration
command. An issue, not a PR — an open major PR in an Atlantis repo is one
`atlantis apply` comment away from a crash-looping database.

## Postgres (semi-automatic)

```bash
scripts/pg-major-upgrade.sh <namespace> <from> <to> [secret]
# e.g.  scripts/pg-major-upgrade.sh cloudreve 15 18
```

The script: dumps the live deployment → creates `postgres-data-v<to>` PVC
(size/class copied live) → runs a throwaway `postgres:<to>` pod on it with the
same secret-sourced `POSTGRES_*` env → restores → prints the exact HCL edits,
the `terraform import` line, and the post-apply cleanup. You commit what it
prints, PR, `atlantis apply`, verify the app, then run the cleanup (old PVC
delete + `state rm` + drop the old PVC resource from HCL).

**Before starting:** Longhorn-snapshot the old PVC (that's the rollback —
until the cleanup PR the old deployment + PVC are untouched, so a revert of
the migration PR is also a full rollback).

**Check the app's compat matrix first** — the ceiling is the app (cloudreve is
fine on 18; n8n historically lags majors), not postgres's latest.

## Why not fully automatic

Renovate edits versions, never structure. The migration needs old+new db alive
simultaneously, an ordered dump job, and a second cleanup phase — that's
structure + state, which version-bump automation can't author safely. The
operator answer for push-button majors is Crunchy PGO (`PGUpgrade` CR) or
Zalando's fork-follow; revisit if the db count grows past "annoying".
