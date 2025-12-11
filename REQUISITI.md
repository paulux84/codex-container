# Requisiti per esecuzione Codex in container sandbox

## Obiettivo generale
Eseguire `codex` all'interno di un container Docker isolato riutilizzando la logica di rete/firewall esistente, ma appoggiandosi a una immagine custom (`codex-sandbox`) già predisposta con Node, `@openai/codex` e strumenti di rete. Lo script `run_in_container.sh` deve lanciare il container, preparare l'ambiente, applicare il firewall e avviare `codex` (anche senza argomenti) nella directory di lavoro montata, con la possibilità di eseguire un hook di setup (`sandbox-setup.sh`) se presente.

## File da produrre/aggiornare
- `codex-cli/scripts/Dockerfile.codex-sandbox`: Dockerfile per l'immagine custom.
- `codex-cli/scripts/run_in_container.sh`: riscritto per usare l'immagine custom e aggiungere l’hook di setup.
- `sandbox-setup.sh`: script di esempio nella directory che sarà montata come workdir (default: `$(pwd)` o `WORKSPACE_ROOT_DIR`).
- `codex-cli/scripts/README_codex_sandbox.md`: mini guida su build immagine e uso script.

Le copie originali in `original_codex/` e `other_implementation_example/` sono di sola lettura e rimangono come riferimento storico.

## Dockerfile.codex-sandbox
- Base image leggera con Node (es. `node:22-slim`).
- Installa: `git`, `ca-certificates`, `curl`, `dnsutils`, strumenti di rete (`iptables`, `iproute2`, `ipset`); gli ambienti linguaggio (Python, Java, Maven, ecc.) sono pensati per essere iniettati a livello di progetto tramite `sandbox-setup.sh` o immagini derivate.
- Installa globalmente `@openai/codex` con `npm install -g @openai/codex` (versione parametrica via `ARG CODEX_VERSION`, default `latest`), configurando `NPM_CONFIG_PREFIX` per evitare problemi di permessi.
- Copia `init_firewall.sh` (presente accanto al Dockerfile) in `/usr/local/bin/init_firewall.sh` e lo rende eseguibile.
- Crea utente non-root `codex` (uid 1000), setta `USER codex`.
- Imposta `WORKDIR /workspace` e `ENV XDG_CONFIG_HOME=/home/codex/.config`.
- Non forza entrypoint; comando di default lasciato a `sleep infinity`/`bash`.

## run_in_container.sh
- Variabili d’ambiente:
  - `CODEX_DOCKER_IMAGE` (default: `codex-sandbox`).
  - `OPENAI_ALLOWED_DOMAINS` (default: `api.openai.com chat.openai.com chatgpt.com auth0.openai.com platform.openai.com openai.com`; i valori forniti vengono **aggiunti** a questi, non li sostituiscono).
  - `WORKSPACE_ROOT_DIR` (se settata diventa default workdir).
  - `CODEX_CONFIG_DIR` (per scegliere da dove montare la config Codex host).
- Uso CLI:
  - Nessun argomento: lancia `codex --full-auto` interattivo nella workdir.
  - `--work_dir <dir> [--init_script <path>] [ARGOMENTI_CODEX...]`: monta `<dir>` su `/app<dir>`; argomenti extra passati a `codex`. Se fornito `--init_script`, lo script viene copiato nella workdir sotto `.codex/.environment/init.sh` ed eseguito all'interno del container prima di `codex`. Non c’è più auto-esecuzione di `sandbox-setup.sh`.
- Nome container derivato dalla workdir (sanitizzata); `cleanup()` e `trap EXIT` per rimozione container.
- Montaggi:
  - `WORK_DIR` host su `/app$WORK_DIR` nel container.
  - Config Codex host: default `$HOME/.codex` (sovrascrivibile con `CODEX_CONFIG_DIR`), poi fallback `~/.config/codex`, altrimenti cartella `codex/` nella workdir (es. contenente `auth.json`); la directory risultante viene montata su `/codex_home` con `CODEX_HOME=/codex_home` mentre `auth.json` viene montato in sola lettura dal suo percorso originale (o da `--auth_file`/`CODEX_AUTH_FILE`) senza copiarlo nella workdir.
  - Directory ambiente: la cartella `WORK_DIR/.codex/.environment` (o il path scelto con `--codex-home <path>/.environment`; se il path è fuori workdir viene chiesta conferma) viene creata sul host e usata come posizione standard per file e download relativi all'ambiente; all'interno del container è esposta come `/codex_home` e resa disponibile agli script tramite la variabile `SANDBOX_ENV_DIR`.
  - Rete / firewall:
    - Avvio container con `--cap-add=NET_ADMIN` e `--cap-add=NET_RAW`.
    - Scrivere domini consentiti (validando formato) in `/etc/codex/allowed_domains.txt` nel container.
    - Eseguire `/usr/local/bin/init_firewall.sh` come root, poi `rm -f` dello script (tollerando errori).
  - Consentire solo loopback e i domini espliciti in `OPENAI_ALLOWED_DOMAINS` (default già include stack OpenAI/ChatGPT; l'elenco passato viene unito ai default); bloccare la rete locale/gateway.
- Hook setup ambiente:
  - In `docker exec` finale: `cd "/app$WORK_DIR"`, eseguire `sandbox-setup.sh` se presente (direttamente se eseguibile, altrimenti con `bash`), poi eseguire `codex --full-auto` con eventuali argomenti.
- Rimozione limitazione argomenti obbligatori: se non ci sono argomenti extra, `codex --full-auto` viene lanciato senza errori.

## sandbox-setup.sh (esempio)
- Shebang bash, `set -euo pipefail`.
- Idempotente: controlla file presenti e prepara dipendenze:
  - Se c’è `requirements.txt`: crea `.venv`, attiva e `pip install -r requirements.txt`.
  - Se c’è `pom.xml`: `mvn -q -DskipTests dependency:go-offline || true`.
  - Se c’è `package.json`: `npm install` nella workdir.
- Stampa messaggi chiari tipo `[sandbox] preparing ...`.

## README_codex_sandbox.md
- Istruzioni per build immagine: `docker build -t codex-sandbox -f Dockerfile.codex-sandbox .`
- Esempi d’uso di `run_in_container.sh` (base, con work_dir, con domini extra).
- Nota che `sandbox-setup.sh` viene eseguito automaticamente se presente nella workdir.
