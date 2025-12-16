#!/usr/bin/env bash
set -euo pipefail

# Configurable versions for Java and Maven
JAVA_MAJOR_VERSION="21"
MAVEN_VERSION="3.9.11"

log() {
  echo "[init-java] $*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "ERROR: required command not found: $1"
    exit 1
  fi
}

# Hook working directory inside the container (run_in_container.sh exports SANDBOX_ENV_DIR=/codex_home)
SANDBOX_ENV_DIR="${SANDBOX_ENV_DIR:-"$PWD/.codex/.environment"}"
TOOLS_DIR="$SANDBOX_ENV_DIR/tools"
JAVA_DIR="$TOOLS_DIR/java-$JAVA_MAJOR_VERSION"
MAVEN_DIR="$TOOLS_DIR/apache-maven-$MAVEN_VERSION"
BIN_DIR="$SANDBOX_ENV_DIR/bin"
BASHRC_PATH="$SANDBOX_ENV_DIR/.bashrc"

mkdir -p "$TOOLS_DIR" "$BIN_DIR"

require_cmd curl
require_cmd tar

install_java() {
  if [[ -x "$JAVA_DIR/bin/java" ]]; then
    if "$JAVA_DIR/bin/java" -version 2>&1 | grep -q "$JAVA_MAJOR_VERSION"; then
      log "Java $JAVA_MAJOR_VERSION già presente in $JAVA_DIR"
      export JAVA_HOME="$JAVA_DIR"
      export PATH="$JAVA_HOME/bin:$PATH"
      return
    fi
    log "Java presente in $JAVA_DIR ma versione diversa, reinstallo"
    rm -rf "$JAVA_DIR"
  fi

  # Adoptium GA build for x64 Linux architecture
  JAVA_URL="https://api.adoptium.net/v3/binary/latest/${JAVA_MAJOR_VERSION}/ga/linux/x64/jdk/hotspot/normal/eclipse"
  log "Scarico JDK ${JAVA_MAJOR_VERSION} da $JAVA_URL"

  (
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    cd "$tmp_dir"
    curl -fsSL "$JAVA_URL" -o jdk.tar.gz
    tar -xzf jdk.tar.gz
    extracted_dir="$(find . -maxdepth 1 -type d -name 'jdk-*' | head -n 1)"
    if [[ -z "${extracted_dir:-}" ]]; then
      log "ERROR: directory JDK non trovata dopo l'estrazione"
      exit 1
    fi
    mkdir -p "$JAVA_DIR"
    mv "$extracted_dir"/* "$JAVA_DIR"/
  )

  export JAVA_HOME="$JAVA_DIR"
  export PATH="$JAVA_HOME/bin:$PATH"
  log "Java ${JAVA_MAJOR_VERSION} installato in $JAVA_HOME"
}

install_maven() {
  if [[ -x "$MAVEN_DIR/bin/mvn" ]]; then
    if "$MAVEN_DIR/bin/mvn" -v 2>&1 | grep -q "Apache Maven $MAVEN_VERSION"; then
      log "Maven $MAVEN_VERSION già presente in $MAVEN_DIR"
      export PATH="$MAVEN_DIR/bin:$PATH"
      return
    fi
    log "Maven presente in $MAVEN_DIR ma versione diversa, reinstallo"
    rm -rf "$MAVEN_DIR"
  fi

  MAVEN_URL="https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
  log "Scarico Maven ${MAVEN_VERSION} da $MAVEN_URL"

  (
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    cd "$tmp_dir"
    curl -fsSL "$MAVEN_URL" -o maven.tar.gz
    tar -xzf maven.tar.gz
    extracted_dir="$(find . -maxdepth 1 -type d -name "apache-maven-${MAVEN_VERSION}" | head -n 1)"
    if [[ -z "${extracted_dir:-}" ]]; then
      log "ERROR: directory Maven non trovata dopo l'estrazione"
      exit 1
    fi
    mv "$extracted_dir" "$MAVEN_DIR"
  )

  export PATH="$MAVEN_DIR/bin:$PATH"
  log "Maven ${MAVEN_VERSION} installato in $MAVEN_DIR"
}

install_java
install_maven

# Expose the binaries also via stable symlinks in $SANDBOX_ENV_DIR/bin
ln -sf "$JAVA_DIR/bin/java" "$BIN_DIR/java"
ln -sf "$JAVA_DIR/bin/javac" "$BIN_DIR/javac"
ln -sf "$MAVEN_DIR/bin/mvn" "$BIN_DIR/mvn"

# Update PATH (even if the caller has a restricted default PATH)
export PATH="$BIN_DIR:$JAVA_DIR/bin:$MAVEN_DIR/bin:$PATH"

# Make the environment persistent for future shells (e.g. interactive docker exec sessions)
#cat >"$ENV_SNIPPET" <<EOF
## shellcheck shell=bash
#export JAVA_HOME="$JAVA_DIR"
#for p in "$BIN_DIR" "$JAVA_DIR/bin" "$MAVEN_DIR/bin"; do
#  case ":\$PATH:" in
#    *":\$p:"*) ;;
#    *) PATH="\$p:\$PATH" ;;
#  esac
#done
#export PATH
#EOF

#if [[ ! -f "$BASHRC_PATH" ]]; then
#  echo 'source "$HOME/.env_init_java.sh" 2>/dev/null || true' >"$BASHRC_PATH"
#elif ! grep -Fq '.env_init_java.sh' "$BASHRC_PATH"; then
#  echo 'source "$HOME/.env_init_java.sh" 2>/dev/null || true' >>"$BASHRC_PATH"
#fi

mkdir -p /home/codex/.m2
cat <<EOF > /home/codex/.m2/settings.xml
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0 https://maven.apache.org/xsd/settings-1.2.0.xsd">
  <localRepository>/app/home/user/.m2/repository</localRepository>
</settings>

EOF


# Final verification
log "java -version:"
java -version 2>&1 || true

log "mvn -v:"
mvn -v 2>&1 || true
