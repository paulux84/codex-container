# Requirements for running Codex in a sandboxed container

This document captures the design goals and functional requirements for
`run_in_container.sh` and the `codex-sandbox` image. It is a **design
reference** for maintainers; end users should start from `README.md`.

---

## High‑level goal

Run the `codex` CLI inside an **isolated Docker container** while:

- reusing the existing network/firewall logic of the `codex-sandbox` image;
- keeping host and container configuration clearly separated;
- providing a simple wrapper script (`run_in_container.sh`) that:
  - launches the container,
  - mounts a project workdir,
  - applies firewall/proxy rules,
  - optionally runs a setup hook,
  - and finally starts `codex` (with or without arguments).

---

## Functional requirements

### 1. Isolated Codex execution

- The wrapper receives a workdir via `--work_dir <path>`.
- It starts a **dedicated container** for that workdir and removes it automatically when Codex exits.
- The workdir from the host is mounted inside the container and used as the Codex working directory.

### 2. Init hook

- An init hook is configurable via `--init_script <path>`.
- The script is copied into `WORK_DIR/.codex/.environment/init.sh` and made executable.
- Inside the container the hook is available as:
  - path: `/app$WORK_DIR/.codex/.environment/init.sh`,
  - environment: `SANDBOX_ENV_DIR=/app$WORK_DIR/.codex/.environment`.
- The hook is executed from the project directory **before** starting `codex`.
- All artifacts produced by the hook must stay under `.codex/.environment`.

### 3. Codex home, config, and sessions

- The container’s Codex home is `/codex_home`, backed by `WORK_DIR/.codex/.environment` on the host.
- `config.toml`:
  - is copied from the host when missing and stored in `WORK_DIR/.codex/.environment/config.toml`,
  - can be explicitly overridden by:
    - `--config <file|dir_with_config.toml>`, or
    - `CODEX_CONFIG_DIR=<dir>`.
- `auth.json`:
  - remains on the host; it is **not** copied into `.codex/.environment`,
  - is searched in this order:
    1. `--auth_file <path>` or `CODEX_AUTH_FILE`,
    2. the directory passed with `--config`,
    3. `CODEX_CONFIG_DIR`,
    4. `~/.codex`,
    5. `$HOME/.config/codex`,
    6. `WORK_DIR/codex`,
    7. `WORK_DIR/.codex`,
    8. a pre‑existing `WORK_DIR/.codex/.environment/auth.json`,
  - when found, it is mounted **read‑only** as `/codex_home/auth.json`.
- Session history:
  - is stored in `WORK_DIR/.codex/.environment/sessions` by default,
  - can be overridden via `--sessions-path <path>`,
  - is not copied from any host‑global location.

### 4. Prompts

- Prompt files should be discoverable from either host‑global or project‑local locations.
- The wrapper searches for the first `prompts` directory using this order:
  1. directory passed to `--config` (if it is a directory),
  2. `CODEX_CONFIG_DIR`,
  3. `~/.codex`,
  4. `~/.config/codex`,
  5. `WORK_DIR/codex`,
  6. `WORK_DIR/.codex`.
- All prompt files found there are copied into `WORK_DIR/.codex/.environment/prompts`.
- Existing prompt files in `.codex/.environment/prompts` must **not** be overwritten.

### 5. Container user and filesystem access

- Codex runs as an unprivileged `codex` user inside the container.
- The `codex` user has full read/write access only to:
  - the mounted workdir,
  - any additional paths explicitly mounted by the wrapper.
- The wrapper **must not** mount the host root directory (`/`); if `--work_dir` resolves to `/`, it is rejected.
- If `WORKSPACE_ROOT_DIR` is set, the resolved `--work_dir` must be a descendant of that directory.

### 6. Network sandboxing and firewall

- The container follows a **default‑deny** outbound policy:
  - loopback traffic is always allowed,
  - local network and gateway access are blocked,
  - outbound traffic is only allowed to:
    - DNS resolvers,
    - a configured HTTP proxy (for example Squid),
    - domains in the allowlist.
- OpenAI/ChatGPT domains are always whitelisted by default (for example `api.openai.com`, `chat.openai.com`, `chatgpt.com`, `auth0.openai.com`, `platform.openai.com`, `openai.com`).
- Additional allowed domains are configured via:
  - `OPENAI_ALLOWED_DOMAINS="example.com another.example.org"`.
- The firewall layer:
  - resolves allowed domains,
  - populates an `ipset` (for example `allowed-domains`),
  - ensures traffic to other hosts is blocked.
- On startup, the wrapper should verify:
  - a blocked host like `https://example.com` is not reachable,
  - `https://api.openai.com` is reachable via the configured proxy.

### 7. Image selection and variants

- The Codex container image is selected via:
  - `CODEX_DOCKER_IMAGE` (for example `codex-sandbox:0.36.0`),
  - otherwise the default `codex-sandbox` image is used.
- The image itself is built with:
  - `--build-arg CODEX_VERSION=x.y.z` to pin the Codex CLI version,
  - multi‑platform support as needed.
- Runtime auto‑upgrade of Codex is **out of scope**; version selection happens at build time via `CODEX_VERSION`.

### 8. Additional mounts

- The wrapper supports multiple read‑only mounts:
  - `--read-only <path>` can be passed multiple times,
  - each path (file or directory) is mounted as read‑only under `/app<path>` in the container.
- Writable mounts outside the workdir (for example a custom `--codex-home` or `--sessions-path` outside the project) are **sensitive**:
  - they must trigger a clear warning,
  - in interactive mode, the user must confirm with `y`,
  - in non‑interactive mode they are rejected by default.

---

## Non‑functional constraints

- The wrapper script should be a small, readable shell script without heavy dependencies.
- Failure modes should be explicit and safe:
  - avoid best‑effort fallbacks that silently weaken isolation,
  - do not proceed if a critical safety check fails (for example workdir validation, firewall setup).
- All behaviour that affects user security or privacy must be documented in `README.md`.

