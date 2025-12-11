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

CONFIG_OVERRIDE_DIR="$TMP_DIR/config_override"
mkdir -p "$CONFIG_OVERRIDE_DIR"
echo "custom-config = true" > "$CONFIG_OVERRIDE_DIR/config.toml"
echo '{"auth":"token"}' > "$CONFIG_OVERRIDE_DIR/auth.json"

cat <<'EOS' > "$MOCK_BIN/docker"
#!/usr/bin/env bash
echo "docker $*" >> "$DOCKER_LOG"
sub="$1"
if [[ "$sub" == "image" ]]; then
  exit 0
elif [[ "$sub" == "inspect" ]]; then
  if [[ "$*" == *"{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"* ]]; then
    echo "172.30.0.2"
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

OUTSIDE_CODEX_HOME="$TMP_DIR/outside_codex"
OUTSIDE_SESSIONS="$TMP_DIR/outside_sessions"

CODEX_VERSION="1.2.3" \
CODEX_DOCKER_IMAGE="codex-sandbox:1.2.3" \
CODEX_DATA_DIR="$OUTSIDE_CODEX_HOME" \
SESSIONS_PATH="$OUTSIDE_SESSIONS" \
WORKSPACE_ROOT_DIR="$WORK_DIR" \
bash "$ROOT_DIR/codex-cli/scripts/run_in_container.sh" \
  -y \
  --config "$CONFIG_OVERRIDE_DIR" >/dev/null

if [[ ! -f "$OUTSIDE_CODEX_HOME/.environment/config.toml" ]]; then
  echo "Expected config.toml to be copied into external codex home when using -y" >&2
  exit 1
fi

if [[ -f "$OUTSIDE_CODEX_HOME/.environment/auth.json" ]]; then
  echo "auth.json should not be copied into the codex home directory" >&2
  exit 1
fi

if ! grep -Fq "docker exec --user codex" "$DOCKER_LOG"; then
  echo "Expected docker exec to include --user codex" >&2
  cat "$DOCKER_LOG" >&2
  exit 1
fi

if ! grep -Fq -- "--mount type=bind,src=$CONFIG_OVERRIDE_DIR/auth.json,dst=/codex_home/auth.json,ro" "$DOCKER_LOG"; then
  echo "Expected docker run to mount auth.json from the override directory" >&2
  cat "$DOCKER_LOG" >&2
  exit 1
fi

echo "run_in_container yes-flag test passed"
