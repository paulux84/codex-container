#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

WORK_DIR="$TMP_DIR/work"
mkdir -p "$WORK_DIR"

HOME="$TMP_DIR/home"
mkdir -p "$HOME/.codex"
echo '{"auth":"from-home"}' >"$HOME/.codex/auth.json"
chmod 600 "$HOME/.codex/auth.json"
export HOME

DOCKER_LOG="$TMP_DIR/docker.log"
export DOCKER_LOG

MOCK_BIN="$TMP_DIR/mockbin"
mkdir -p "$MOCK_BIN"

CONFIG_OVERRIDE_DIR="$TMP_DIR/config_override"
mkdir -p "$CONFIG_OVERRIDE_DIR"
echo "custom-config = true" >"$CONFIG_OVERRIDE_DIR/config.toml"

cat <<'EOS' >"$MOCK_BIN/docker"
#!/usr/bin/env bash
echo "docker $*" >>"$DOCKER_LOG"
sub="$1"
if [[ "$sub" == "image" ]]; then
  exit 0
elif [[ "$sub" == "inspect" ]]; then
  if [[ "$*" == *"{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"* ]]; then
    echo "172.40.0.2"
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

CODEX_VERSION="2.3.4" \
CODEX_DOCKER_IMAGE="codex-sandbox:2.3.4" \
WORKSPACE_ROOT_DIR="$WORK_DIR" \
bash "$ROOT_DIR/codex-cli/scripts/run_in_container.sh" \
  --config "$CONFIG_OVERRIDE_DIR" >/dev/null

if [[ -f "$WORK_DIR/.codex/.environment/auth.json" ]]; then
  echo "auth.json should not be created in the workdir when using host HOME auth" >&2
  exit 1
fi

if ! grep -Fq -- "--mount type=bind,src=$HOME/.codex/auth.json,dst=/codex_home/auth.json,ro" "$DOCKER_LOG"; then
  echo "Expected docker run to mount auth.json from \$HOME/.codex when --config lacks auth" >&2
  cat "$DOCKER_LOG" >&2
  exit 1
fi

echo "run_in_container config-without-auth test passed"
