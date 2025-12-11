# Requisiti per esecuzione Codex in container sandbox

## Obiettivo generale
Eseguire `codex` all'interno di un container Docker isolato bloccando il traffico verso l'esterno usando squid firewall oppure un acl tramite iptables, questo e' ottenuto appoggiandosi a una immagine custom (`codex-sandbox`) già predisposta con Node, `@openai/codex` e strumenti di rete. Lo script `run_in_container.sh` deve lanciare il container ed eventuale proxy firewall, preparare l'ambiente, applicare/configurare il firewall e avviare `codex` (anche senza argomenti) nella directory di lavoro montata, con la possibilità di eseguire un hook di setup se presente.

## Requisiti funzionali
- Esecuzione Codex isolata sulla workdir passata allo script (`--work_dir`), con container dedicato e cleanup automatico.
- Hook di init configurabile via `--init_script`: esegue solo `/app$WORK_DIR/.codex/.environment/init.sh` se esiste ed è eseguibile, con artefatti isolati in `.codex/.environment` e variabile `SANDBOX_ENV_DIR` nel container.
- Configurazioni Codex su `/app$WORK_DIR/.codex/.environment` (montata come `/codex_home`): `config.toml` forzabile con `--config` (file oppure directory contenente `config.toml`, sovrascrive), altrimenti copiato dall’host se mancante; `auth.json` resta sul path host (es. `~/.codex`, directory passata a `--config` o valore esplicito `--auth_file` / `CODEX_AUTH_FILE`) e viene montato in sola lettura come `/codex_home/auth.json`; sessioni dedicate nel container (default `.codex/.environment/sessions`, override `--sessions-path`, non clonate dall’host).
- Utente `codex` non-root nel container con piena lettura/scrittura sulla workdir montata.
- Firewall interno configurabile (`OPENAI_ALLOWED_DOMAINS`) con default deny e allowlist base per i domini OpenAI/ChatGPT; verifica di blocco e di reachability OpenAI; loopback sempre consentito, rete locale/gateway bloccati.
- Selezione immagine container via `CODEX_DOCKER_IMAGE` e default workdir via `WORKSPACE_ROOT_DIR`.
- Immagini pre-taggate per Node 18/20/22 (`build_node_variants.sh`), alias `codex-sandbox` su Node 22.
- Mount multipli in sola lettura con `--read-only <path>` (ripetibile, file o directory, montati in `ro` su `/app<path>`); selezione/auto-upgrade versione Codex al runtime non ancora supportata (solo `CODEX_VERSION` in build).
- Protezione workdir: i percorsi passati a `--work_dir` vengono risolti e se risultano `/` vengono rifiutati (niente mount della root host nel container).
- Montare percorsi **writable** fuori dalla workdir (es. `--codex-home`, `--sessions-path`) richiede conferma interattiva e comporta l’esposizione in scrittura di quei path host al container: rispondi `y` solo se lo vuoi davvero.
