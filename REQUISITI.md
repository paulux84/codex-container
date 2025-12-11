# Requisiti per esecuzione Codex in container sandbox

## Obiettivo generale
Eseguire `codex` all'interno di un container Docker isolato riutilizzando la logica di rete/firewall esistente e l'immagine custom `codex-sandbox` (con Node e `@openai/codex` già installati). Lo script `run_in_container.sh` deve lanciare il container, preparare l'ambiente, applicare il firewall/proxy e avviare `codex` (anche senza argomenti) nella directory di lavoro montata, con la possibilità di eseguire un hook di setup se presente.

## Requisiti funzionali
- Esecuzione Codex isolata sulla workdir passata con `--work_dir`, con container dedicato e cleanup automatico.
- Hook di init configurabile via `--init_script`: viene copiato come `/app$WORK_DIR/.codex/.environment/init.sh` ed eseguito nel container prima di `codex`; tutti gli artefatti restano in `.codex/.environment`, esposta agli script come `SANDBOX_ENV_DIR`.
- Configurazioni Codex in `/app$WORK_DIR/.codex/.environment` (montata come `/codex_home`): `config.toml` copiato se mancante; `auth.json` resta sul path host scelto (`--auth_file`/`CODEX_AUTH_FILE` o directory di config) e viene montato in sola lettura; sessioni dedicate nel container (default `.codex/.environment/sessions`, override `--sessions-path`).
- Utente `codex` non-root nel container con pieno accesso in lettura/scrittura alla workdir montata.
- Firewall interno a default deny: loopback sempre aperto, rete locale/gateway bloccate; traffico in uscita consentito solo verso DNS pubblici e verso il proxy (Squid interno o proxy esterno); Squid applica ACL `allowed_sites` sui domini OpenAI/ChatGPT (lista di default più extra passati) e lo script verifica che `https://example.com` sia bloccato e `https://api.openai.com` raggiungibile via proxy.
- Selezione immagine via `CODEX_DOCKER_IMAGE` e default workdir via `WORKSPACE_ROOT_DIR`; sono disponibili varianti Node pre-taggate (alias `codex-sandbox` su Node 22).
- Mount multipli in sola lettura con `--read-only <path>` (ripetibile, file o directory, montati `ro` su `/app<path>`); è vietato montare `/` per evitare l'esposizione dell'intero host.
- Protezione workdir: i percorsi passati a `--work_dir` vengono risolti e se risultano `/` lo script si rifiuta di usarli; se `WORKSPACE_ROOT_DIR` è impostata, la workdir deve cadere al suo interno.
