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
#   LEAK_IV_PORT=7862        host port (the MCP endpoint is http://localhost:$LEAK_IV_PORT/sse)
#   LEAK_IV_NAME=leak-iv     container name
#   LEAK_IV_REF=tengoku-env  branch/tag of mikael-bashir/leak-iv to build
#
# Afterwards:  docker stop leak-iv · docker start leak-iv · docker logs -f leak-iv
#              docker rm -f leak-iv && docker rmi leak-iv:tengoku   (remove everything)
# Needs Docker and about 20 GB of free disk (image ~15 GB, cache download ~2 GB).
set -euo pipefail

PORT="${LEAK_IV_PORT:-7862}"
NAME="${LEAK_IV_NAME:-leak-iv}"
REF="${LEAK_IV_REF:-tengoku-env}"
IMAGE="leak-iv:tengoku"
REPO="https://github.com/mikael-bashir/leak-iv.git"
TREE="https://github.com/competemath/tengoku"
LOG="${TMPDIR:-/tmp}/leak-iv-install.log"

say()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

cat <<EOF

  Leak IV installer
  =================
  This will, on THIS machine:

   1. Build a Docker image "$IMAGE" (about 15 GB, inside Docker's own disk)
      from $REPO (branch $REF):
        - Ubuntu 22.04 base, build tools, Python
        - the Lean 4 toolchain the Tengoku tree pins (installed by elan)
        - the Tengoku tree's source from $TREE, pinned to the commit
          of its newest published build cache, and that cache: ~2 GB
          downloaded from the repository's GitHub releases, ~11 GB once
          unpacked. Nothing is compiled — the cache covers the tree exactly.
   2. Start a container "$NAME" listening on http://127.0.0.1:$PORT
      (reachable only from this machine).

  Nothing is installed outside Docker. A temporary clone under ${TMPDIR:-/tmp}
  is removed when this finishes.

  Expect about 10 minutes end to end (mostly downloads). Full build log: $LOG

  Undo everything later:  docker rm -f $NAME && docker rmi $IMAGE

EOF

say "1/5  Checking prerequisites"
command -v docker >/dev/null 2>&1 || die "Docker is required: https://docs.docker.com/get-docker/"
docker info >/dev/null 2>&1 || die "Docker is installed but not running — start Docker Desktop (or the daemon) and re-run."
command -v git  >/dev/null 2>&1 || die "git is required."
command -v curl >/dev/null 2>&1 || die "curl is required."
note "docker, git, curl: found"
if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  note "a container named $NAME already exists — it will be replaced"
fi
avail_gb="$(docker run --rm alpine:3 sh -c 'df -k / | tail -1' 2>/dev/null | awk '{printf "%d", $4/1048576}' || true)"
if [ -n "${avail_gb:-}" ]; then
  note "Docker reports ${avail_gb} GB free on its disk (this needs about 20 GB)"
  [ "$avail_gb" -ge 20 ] || note "warning: that may not be enough — docker system prune, or raise the disk limit in Docker Desktop settings"
else
  note "could not measure Docker's free disk (skipping the check)"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

say "2/5  Fetching the Leak IV source ($REF) into a temporary folder"
git clone --quiet --depth 1 --branch "$REF" "$REPO" "$work/leak-iv"
note "$(git -C "$work/leak-iv" rev-parse --short HEAD) — $work/leak-iv (deleted afterwards)"

say "3/5  Building $IMAGE — each step below is one layer of the image"
note "(full output is in $LOG; only the milestones are shown here)"
: > "$LOG"
DOCKER_BUILDKIT=1 docker build --pull --progress=plain -t "$IMAGE" "$work/leak-iv" 2>&1 | tee -a "$LOG" | awk '
  function describe(cmd) {
    if (cmd ~ /apt-get install/ && cmd ~ /zstd/)   return "installing zstd + gh (to fetch and unpack the tree cache)"
    if (cmd ~ /apt-get install/)                   return "installing system packages (curl, git, build tools, Python)"
    if (cmd ~ /elan-init/)                         return "installing elan, the Lean toolchain manager"
    if (cmd ~ /astral\.sh\/uv/)                    return "installing uv (Python package manager)"
    if (cmd ~ /uv python install/)                 return "installing Python 3.11 for the MCP server"
    if (cmd ~ /uv venv/)                           return "creating the server'"'"'s Python environment"
    if (cmd ~ /uv pip install/)                    return "installing the MCP server'"'"'s Python packages"
    if (cmd ~ /git clone/ && cmd ~ /tengoku/)      return "cloning the Tengoku tree source (history only, contents on demand) from github.com/competemath/tengoku — ~1-2 min"
    if (cmd ~ /cache\.sh get/)                     return "pinning the tree to its newest cache commit, then downloading that cache (~2 GB) from GitHub releases and unpacking it (~11 GB) — ~3-5 min"
    if (cmd ~ /lake build/)                        return "verifying the cache: a replay only, nothing compiles (this also installs the pinned Lean toolchain) — ~1-2 min"
    if (cmd ~ /virtual_sandbox/)                   return ""
    return cmd
  }
  /^#[0-9]+ \[stage-0 [0-9]+\/[0-9]+\] RUN / {
    id = $1; sub(/^#/, "", id)
    step = $2 " " $3; gsub(/[\[\]]/, "", step); sub(/^stage-0 /, "", step)
    cmd = $0; sub(/^#[0-9]+ \[stage-0 [0-9]+\/[0-9]+\] RUN /, "", cmd); sub(/--mount=[^ ]+ /, "", cmd)
    d = describe(cmd)
    if (d != "") { printf "    step %s  %s\n", step, d; fflush(); started[id] = 1 }
    next
  }
  /^#[0-9]+ (exporting to image|exporting layers)/ { id = $1; sub(/^#/, "", id); if (!(id in started)) { printf "    saving the image to Docker (~15 GB)\n"; fflush(); started[id] = 1 } next }
  /^#[0-9]+ DONE [0-9.]+s/ { id = $1; sub(/^#/, "", id); if (id in started) { printf "             done in %s\n", $3; fflush() } next }
  /^#[0-9]+ ERROR/ { printf "    \033[1;31mfailed:\033[0m %s\n", $0; fflush(); next }
  /fetching cache-|unpacked cache-|no published cache|tree pinned to cache commit/ { line = $0; sub(/^#[0-9]+ [0-9.]+ /, "", line); printf "             %s\n", line; fflush(); next }
'
note "image ready: $(docker images "$IMAGE" --format '{{.Size}}')"

say "4/5  Starting the container $NAME on http://127.0.0.1:$PORT"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart unless-stopped -p "127.0.0.1:${PORT}:7860" "$IMAGE" >/dev/null
note "started (it restarts with Docker unless you stop it)"

say "5/5  Waiting for the verifier to answer — the first start loads the tree, about a minute"
up=""
for _ in $(seq 1 90); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H 'Accept: text/event-stream' "http://127.0.0.1:${PORT}/sse" || true)"
  if [ "$code" = "200" ]; then up=1; break; fi
  sleep 2
done
[ -n "$up" ] || { docker logs --tail 30 "$NAME" >&2 || true; die "Leak IV did not come up on port $PORT — see the container log above (docker logs -f $NAME)"; }

cat <<EOF

  Leak IV is running on this machine.

    MCP endpoint:   http://localhost:${PORT}/sse
    On the site:    MCP Servers -> add   name: Leak_IV   url: http://localhost:${PORT}/sse

    stop / start:   docker stop ${NAME}   ·   docker start ${NAME}
    logs:           docker logs -f ${NAME}
    remove it all:  docker rm -f ${NAME} && docker rmi ${IMAGE}
    update later:   call its tengoku_sync tool from the site, or re-run this installer

EOF
