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

EXTERNAL_RO_FILE="$TMP_DIR/outside.txt"
echo "ro" >"$EXTERNAL_RO_FILE"

cat <<'EOS' >"$MOCK_BIN/docker"
#!/usr/bin/env bash
echo "docker $*" >>"$DOCKER_LOG"
sub="$1"
if [[ "$sub" == "image" ]]; then
  exit 0
elif [[ "$sub" == "inspect" ]]; then
  # respond to network/container inspect IP query
  if [[ "$*" == *"{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"* ]]; then
    echo "172.50.0.2"
  fi
  exit 0
fi
case "$sub" in
  pull|cp|run|exec|build|rm|network)
    exit 0
    ;;
esac
exit 0
EOS

chmod +x "$MOCK_BIN/docker"
export PATH="$MOCK_BIN:$PATH"

CODEX_VERSION="9.9.9" \
CODEX_DOCKER_IMAGE="codex-sandbox:9.9.9" \
WORKSPACE_ROOT_DIR="$WORK_DIR" \
bash "$ROOT_DIR/codex-cli/scripts/run_in_container.sh" \
  --work_dir "$WORK_DIR" \
  --read-only "$EXTERNAL_RO_FILE" \
  >/dev/null

expected_mount="--mount type=bind,src=$EXTERNAL_RO_FILE,dst=/app$EXTERNAL_RO_FILE,ro"

if ! grep -Fq -- "$expected_mount" "$DOCKER_LOG"; then
  echo "Expected docker run to include read-only mount for external path: $expected_mount" >&2
  cat "$DOCKER_LOG" >&2
  exit 1
fi

echo "run_in_container read-only external path test passed"
