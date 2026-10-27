# Pelican panel — side-by-side setup, then cutover

Pelican replaces Pterodactyl 1.15.2. It is **not** a parallel upgrade of the same
install: `pelican migrate` upgrades the Pterodactyl database **in place** and
Pterodactyl cannot read the upgraded schema afterwards. So the two panels never
share a database.

What *can* run at the same time:

| Layer | Both at once? | Why |
|---|---|---|
| Panel | ✅ | Pelican gets its own MariaDB (10.11+) holding a **clone** of the Pterodactyl DB. Pterodactyl keeps its own 10.5 DB, untouched. |
| Wings / nodes | ❌ | One `wings` process talks to exactly one panel URL + node token. Until each node is cut over, Pelican shows those nodes (and their servers) offline. |

Consequence of the clone: anything written to Pterodactyl after the dump (new
servers, users, egg edits, API keys) does not exist in the Pelican preview. Re-dump
immediately before the real cutover.

## 1. Prerequisites already satisfied

- Pterodactyl **1.15.2** ≥ 1.11.4 (Pelican's minimum).
- New MariaDB is **10.11**; Pterodactyl's 10.5 is too old for Pelican.

## 2. Namespace + unmanaged secret (out-of-band, before apply)

The panel needs `pelican-secret` in ns `pelican` with three keys
(`dealchis` pattern — secretKeyRef only, never in the repo):

| key | value |
|---|---|
| `APP_KEY` | **copied verbatim** from Pterodactyl `/app/var/.env` — it decrypts 2FA secrets and encrypted settings; a fresh key silently breaks them |
| `DB_ROOT_PASSWORD` | new random |
| `DB_PASSWORD` | new random (user `pelican`, db `pelican`) |

```bash
kubectl create namespace pelican
APP_KEY=$(kubectl -n pterodactyl exec deploy/panel -- sh -c 'sed -n "s/^APP_KEY=//p" /app/var/.env')
kubectl -n pelican create secret generic pelican-secret \
  --from-literal=APP_KEY="$APP_KEY" \
  --from-literal=DB_ROOT_PASSWORD="$(openssl rand -hex 24)" \
  --from-literal=DB_PASSWORD="$(openssl rand -hex 24)"
```
Then `terraform import 'kubernetes_namespace_v1.pelican' pelican` once, so TF
adopts the namespace instead of creating it.

## 3. Apply

`atlantis apply -p terraform-apps` (or local plan/apply with the TF_VAR_* fetched
from `atlantis-app-vars`). Creates: ns, `pelican-db-pvc` 20Gi,
`pelican-data-pvc` 10Gi, `db` (mariadb:10.11), `panel`
(`ghcr.io/pelican/panel:v1.0.0-beta38`), 2 services, IngressRoute
`pelican.vanderloch.com` (websecure, `lochis-tls`).

The panel starts with `APP_INSTALLED=true` but an **empty** database, which is
expected — the clone in step 4 fills it. Do not open the web installer; this is
the upgrade path, not a fresh install.

## 4. Clone the Pterodactyl DB into Pelican's

Read-only on the source. Runs while Pterodactyl serves traffic.

```bash
kubectl -n pterodactyl exec deploy/database -- sh -c \
  'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction \
   --no-tablespaces --default-character-set=utf8mb4 panel' \
| kubectl -n pelican exec -i deploy/db -- sh -c \
  'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" pelican'
```

## 5. Migrate the clone

Restart the panel so the entrypoint waits for the DB and runs
`php artisan migrate --force`, then seed:

```bash
kubectl -n pelican rollout restart deploy/panel
kubectl -n pelican logs -f deploy/panel   # wait for "Starting Supervisord"
kubectl -n pelican exec deploy/panel -- php artisan db:seed --force
```

If the wait never ends, the migration failed — read the logs before retrying.

## 6. Verify the preview

- `https://pelican.vanderloch.com` — login with an existing Pterodactyl account.
- Users, servers, eggs, databases, schedules, subusers, backups, API keys should
  all be present (old `ptla_`/`ptlc_` API keys keep working).
- Nests → tags on eggs; locations → tags on nodes; root admins → Root Admin role.
- Nodes and servers appear **offline** — expected, wings still points at the
  Pterodactyl panel. Panel-side config editing works.

## 7. Cutover (per node — the `wings` half)

For each node, after a final fresh dump+restore (step 4) so the preview is current:

```bash
sudo systemctl stop wings
sudo curl -fsSL -o /usr/local/bin/wings \
  "https://github.com/pelican/wings/releases/latest/download/wings_linux_amd64"
sudo chmod +x /usr/local/bin/wings
sudo mkdir -p /etc/pelican
sudo cp /etc/pterodactyl/config.yml /etc/pelican/config.yml
# update /etc/systemd/system/wings.service: WorkingDirectory=/etc/pelican
sudo systemctl daemon-reload && sudo systemctl start wings
```

Then disable the Pterodactyl panel route so nobody writes to the old DB.

## 8. After the cutover

- Delete `pterodactyl-var-pvc` / `pterodactyl-db-pvc` only after a week of stable
  Pelican + a verified DB backup (`backups/`).
- Remove ns `pterodactyl` and its IngressRoute.
- Themes and panel modifications do not carry over — look for a plugin instead.
