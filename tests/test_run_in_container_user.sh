#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

WORK_DIR="$TMP_DIR/work"
mkdir -p "$WORK_DIR"

HOME="$TMP_DIR/home"
mkdir -p "$HOME/.codex"
export HOME

DOCKER_LOG="$TMP_DIR/docker.log"
export DOCKER_LOG

MOCK_BIN="$TMP_DIR/mockbin"
mkdir -p "$MOCK_BIN"

cat <<'EOS' > "$MOCK_BIN/docker"
#!/usr/bin/env bash
echo "docker $*" >> "$DOCKER_LOG"
sub="$1"
if [[ "$sub" == "image" ]]; then
  # docker image inspect ...
  exit 0
fi
case "$sub" in
  pull|cp|run|exec|build|rm)
    exit 0
    ;;
esac
exit 0
EOS

chmod +x "$MOCK_BIN/docker"
export PATH="$MOCK_BIN:$PATH"

CODEX_VERSION="1.2.3" \
CODEX_DOCKER_IMAGE="codex-sandbox:1.2.3" \
WORKSPACE_ROOT_DIR="$WORK_DIR" \
bash "$ROOT_DIR/codex-cli/scripts/run_in_container.sh" >/dev/null

if ! grep -Fq "docker exec --user codex" "$DOCKER_LOG"; then
  echo "Expected docker exec to include --user codex" >&2
  cat "$DOCKER_LOG" >&2
  exit 1
fi

echo "run_in_container user test passed"
