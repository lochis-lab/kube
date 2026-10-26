#!/bin/sh
# apps/ render+apply for Atlantis custom workflow. Called as:
#   scripts/kubectl-apps.sh plan   <dir>   — render, gate, dry-run (names only), count-check
#   scripts/kubectl-apps.sh apply  <dir>   — render, gate, apply rendered copy
# Design rules (from incidents): unique mktemp workdir (no races), explicit
# placeholder vars, fail-fast on missing env, no secrets in output.
set -eu
MODE="${1:?plan|apply}"; SRC="${2:?apps dir}"

# every placeholder used in apps/** must have a render var defined here
render() {
  d=$(mktemp -d)
  cp -rL "$SRC"/. "$d"/
  for f in $(grep -rl '__[A-Z_]*__' "$d" 2>/dev/null || true); do
    sed -i -e "s|__NFS_MEDIA_SERVER__|${NFS_MEDIA_SERVER:?env missing}|g" \
           -e "s|__SEARXNG_SECRET__|${SEARXNG_SECRET:?env missing}|g" \
           -e "s|__WEBSHARE_PROXY_URL__|${WEBSHARE_PROXY_URL:?env missing}|g" "$f"
  done
  if grep -rq '__[A-Z_]*__' "$d"; then
    echo "ERROR: unresolved placeholders remain (add var to atlantis-app-vars + this script):"
    grep -rho '__[A-Z_]*__' "$d" | sort -u; rm -rf "$d"; exit 1
  fi
  echo "$d"
}

case "$MODE" in
  plan)
    d=$(render)
    n=$(grep -Rh '^kind:' "$d" | wc -l)
    kubectl apply -R -f "$d" --dry-run=server -o name 2>/dev/null | tee "$d"/.applied | sed 's/^/would-apply: /'
    a=$(wc -l < "$d"/.applied)
    if [ "$a" != "$n" ]; then
      echo "ERROR: only $a/$n objects validated — one failed silently (stderr suppressed)"; rm -rf "$d"; exit 1
    fi
    rm -rf "$d"
    ;;
  apply)
    d=$(render)
    kubectl apply -R -f "$d"
    rm -rf "$d"
    ;;
  *) echo "unknown mode: $MODE"; exit 1;;
esac
