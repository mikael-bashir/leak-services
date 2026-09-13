#!/usr/bin/env bash
# Leak IV on your machine, on the current Tengoku tree.
#
#   curl -fsSL https://raw.githubusercontent.com/mikael-bashir/leak-services/main/install-leak-iv.sh | bash
#
# Builds the Leak IV image from its `tengoku-env` branch — the verifier's
# resident `lake serve` runs inside the Tengoku tree, whose published build
# cache is fetched during the build so the whole thing takes minutes rather
# than the hours a from-source build would — and starts it as a container.
#
#   LEAK_IV_PORT=7862   host port (the MCP endpoint is http://localhost:$LEAK_IV_PORT/sse)
#   LEAK_IV_NAME=leak-iv  container name
#   LEAK_IV_REF=tengoku-env  branch/tag of mikael-bashir/leak-iv to build
#
# Afterwards:  docker stop leak-iv · docker start leak-iv · docker logs -f leak-iv
#              docker rm -f leak-iv && docker rmi leak-iv:tengoku   (remove everything)
# Needs Docker and about 20 GB of free disk (image ~15 GB, cache download a few GB).
set -euo pipefail

PORT="${LEAK_IV_PORT:-7862}"
NAME="${LEAK_IV_NAME:-leak-iv}"
REF="${LEAK_IV_REF:-tengoku-env}"
IMAGE="leak-iv:tengoku"
REPO="https://github.com/mikael-bashir/leak-iv.git"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "Docker is required: https://docs.docker.com/get-docker/"
docker info >/dev/null 2>&1 || die "Docker is installed but not running — start Docker Desktop (or the daemon) and re-run."
command -v git >/dev/null 2>&1 || die "git is required."
command -v curl >/dev/null 2>&1 || die "curl is required."

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  say "a container named $NAME already exists — it will be replaced"
fi

# Rough headroom check on Docker's data volume (the VM on macOS/Windows).
avail_gb="$(docker run --rm alpine:3 sh -c 'df -k / | tail -1' 2>/dev/null | awk '{printf "%d", $4/1048576}')"
if [ -n "${avail_gb:-}" ] && [ "$avail_gb" -lt 20 ]; then
  say "warning: Docker reports only ${avail_gb} GB free; the build needs about 20 GB (docker system prune, or raise the disk limit in Docker Desktop settings)"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

say "fetching Leak IV ($REF)"
git clone --quiet --depth 1 --branch "$REF" "$REPO" "$work/leak-iv"

say "building $IMAGE on the current Tengoku tree (minutes with the tree's build cache)"
DOCKER_BUILDKIT=1 docker build --pull -t "$IMAGE" "$work/leak-iv"

say "starting $NAME on port $PORT"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart unless-stopped -p "127.0.0.1:${PORT}:7860" "$IMAGE" >/dev/null

say "waiting for the verifier to answer (the first start warms the tree, ~1 minute)"
up=""
for _ in $(seq 1 90); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H 'Accept: text/event-stream' "http://127.0.0.1:${PORT}/sse" || true)"
  if [ "$code" = "200" ]; then up=1; break; fi
  sleep 2
done
[ -n "$up" ] || { docker logs --tail 30 "$NAME" >&2 || true; die "Leak IV did not come up on port $PORT — see the logs above (docker logs -f $NAME)"; }

cat <<EOF

Leak IV is running.

  MCP endpoint:   http://localhost:${PORT}/sse
  Add it on the site under MCP Servers as  name: Leak_IV   url: http://localhost:${PORT}/sse

  stop / start:   docker stop ${NAME}   ·   docker start ${NAME}
  logs:           docker logs -f ${NAME}
  remove it all:  docker rm -f ${NAME} && docker rmi ${IMAGE}
  update later:   call its tengoku_sync tool, or re-run this installer
EOF
