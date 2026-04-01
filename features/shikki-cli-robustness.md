# Feature: Shikki CLI Robustness
> Created: 2026-04-01 | Status: Phase 3 — Business Rules | Owner: @Daimyo

## Context
Le script `./shikki` (CLI principal du Dev OS) crashe lors de `init` et `start` dès qu'il y a un état résiduel (ports occupés, PIDs stale, containers déjà running). Le script n'est pas idempotent et ne gère pas le lifecycle complet des services qu'il lance.

## Inspiration
### Diagnostic (2026-04-01)

Exécution de `./shikki init` depuis la racine du repo — résultat : **crash** à l'étape backend avec `AddrInUse: Address already in use (os error 48)`.

| # | Bug | Source | Sévérité | Impact |
|---|-----|--------|:--------:|:------:|
| 1 | Port 3900 déjà occupé → crash immédiat | @Sensei | **Bloquant** | Init inutilisable si un processus orphelin existe |
| 2 | Pas de `stop` avant re-init | @Sensei | **Bloquant** | Re-init systématiquement cassé |
| 3 | PID stale sans détection | @Kintsugi | Medium | Faux positifs dans `is_running` |
| 4 | `set -e` → arrêt brutal sans cleanup | @Sensei | Medium | Init à moitié fait, état corrompu |
| 5 | `docker compose` recreate containers inutilement | @Sensei | Low | Risque de perte de données si volumes mal montés |
| 6 | Pas d'idempotence (`init` vs `start`) | @Kintsugi | Medium | UX confuse, pas de guard |
| 7 | Chemins relatifs fragiles pour deno | @Sensei | Low | Fragile si CWD change |
| 8 | `status` route vers `do_health` → `do_status` jamais appelé | @Sensei | Medium | Code mort, fonctionnalité manquante |

### Selected Ideas
Tous les 8 bugs sont retenus — ils forment un ensemble cohérent de robustesse CLI.

## Synthesis

**Goal**: Rendre `./shikki init` et `./shikki start` idempotents et résistants à tout état résiduel.

**Scope**:
- Cleanup des ports orphelins avant démarrage (3900, 5174)
- Stop propre avant re-init
- Validation PID + port (pas juste `kill -0`)
- Gestion d'erreur sans `set -e` brutal ou avec trap cleanup
- Skip docker containers déjà healthy
- Guard `is_initialized` dans `do_init` avec option `--force`
- Chemins absolus pour deno/vite
- Fix routing `status` vs `health`

**Out of scope**:
- Refonte complète du script (migration vers un autre langage)
- Ajout de nouvelles commandes
- Modifications du backend Deno ou du frontend Vue

**Success criteria**:
- `./shikki init` réussit même si des services sont déjà running
- `./shikki init` suivi d'un 2e `./shikki init` fonctionne sans intervention
- `./shikki start` récupère des orphelins sur les ports
- `./shikki status` affiche bien les projets et worktrees (pas juste health)
- Aucune régression sur `stop`, `new`, `notify`

**Dependencies**: Aucune — tout est dans `shikki` (script bash auto-contenu)

## Business Rules

```
BR-01: Avant de démarrer le backend (port 3900), tuer tout processus existant sur ce port
BR-02: Avant de démarrer le frontend (port 5174), tuer tout processus existant sur ce port
BR-03: `do_init` doit appeler `do_stop` si des services sont déjà running
BR-04: `do_init` sur un workspace déjà initialisé affiche un message et sort (sauf --force)
BR-05: `is_running()` doit vérifier le PID ET que le port correspondant est bien occupé par ce PID
BR-06: Si le backend crash au démarrage, le frontend ne doit PAS être lancé (déjà le cas via set -e, mais avec cleanup)
BR-07: `docker compose up -d` ne doit PAS recreate des containers déjà running et healthy
BR-08: Le chemin du serveur deno doit être absolu ($SCRIPT_DIR/src/backend/src/server.ts)
BR-09: Le chemin de vite doit être lancé depuis un CWD absolu
BR-10: `./shikki status` doit router vers `do_status()` (projets + worktrees + services)
BR-11: `./shikki health` doit router vers `do_health()` (rapport santé détaillé)
BR-12: En cas d'échec de démarrage d'un service, un message clair indique le problème ET les logs à consulter
BR-13: Le script doit avoir un trap EXIT pour cleanup en cas d'interruption (Ctrl+C pendant init)
```

## Test Plan

Tests manuels (script bash — pas de framework de test unitaire) :

### Scénario 1: Init propre (first time)
```
BR-01,02 → Aucun orphelin → init démarre normalement
BR-04    → .env n'existe pas → copie .env.example
BR-07    → Containers absents → docker compose up -d crée tout
```

### Scénario 2: Re-init (déjà initialisé)
```
BR-03    → Services running → do_stop appelé automatiquement
BR-04    → .env existe → message "already initialized", exit 0
BR-04    → .env existe + --force → do_stop + re-init complet
```

### Scénario 3: Port orphelin
```
BR-01    → PID 18914 sur port 3900 → tué avant lancement backend
BR-02    → PID sur port 5174 → tué avant lancement frontend
BR-05    → PID dans .pids/backend.pid est stale (processus mort) → détecté, fichier nettoyé
```

### Scénario 4: Docker containers déjà running
```
BR-07    → db, ollama, ntfy déjà running+healthy → pas de recreate, skip avec ✓
BR-07    → ollama running mais pas healthy → wait + timeout
```

### Scénario 5: Crash mid-init
```
BR-06    → Backend crash (port pris) → frontend pas lancé, message d'erreur clair
BR-12    → Message affiche "Check .pids/backend.log"
BR-13    → Ctrl+C pendant init → trap nettoie les PIDs écrits
```

### Scénario 6: Routing des commandes
```
BR-10    → ./shikki status → affiche projets, worktrees, services docker, backend, frontend
BR-11    → ./shikki health → affiche rapport santé détaillé (JSON parsed)
```

## Architecture

### Fichier unique : `shikki`

| Section | Modification | BRs |
|---------|-------------|-----|
| `kill_port()` | **Nouvelle fonction** — kill orphelin sur un port donné | BR-01, BR-02 |
| `is_running()` | Vérifier PID + port match via `lsof` | BR-05 |
| `cleanup_stale_pids()` | **Nouvelle fonction** — nettoyer `.pids/` des PIDs morts | BR-05 |
| `do_init()` | Guard `is_initialized` + `--force`, appel `do_stop` | BR-03, BR-04 |
| `do_init()` / `do_start()` | Appel `kill_port 3900` avant backend, `kill_port 5174` avant frontend | BR-01, BR-02 |
| `do_init()` / `do_start()` | Skip docker containers déjà running+healthy | BR-07 |
| `do_init()` / `do_start()` | Chemins absolus pour deno et vite | BR-08, BR-09 |
| `do_init()` / `do_start()` | Trap EXIT pour cleanup | BR-13 |
| Case routing (main) | `status) do_status ;;` et `health) do_health ;;` | BR-10, BR-11 |
| Messages d'erreur | Uniformiser avec log consultable | BR-12 |

### Nouvelles fonctions

```bash
kill_port() {
  local port="$1"
  local pid=$(lsof -ti :"$port" 2>/dev/null || true)
  if [ -n "$pid" ]; then
    echo -e "  Killing process on port $port (PID $pid)..."
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  fi
}

cleanup_stale_pids() {
  for pidfile in "$PID_DIR"/*.pid; do
    [ -f "$pidfile" ] || continue
    local pid=$(cat "$pidfile")
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$pidfile"
    fi
  done
}
```

### Flux modifié de `do_init()`

```
1. Guard: is_initialized && no --force → exit "use start or --force"
2. If services running → do_stop
3. check_prereqs
4. .env setup
5. mkdir projects/ features/ backups/
6. Docker: check each container → skip if running+healthy, else up -d
7. Wait for db + ollama (existant)
8. kill_port 3900
9. Start backend (chemin absolu)
10. kill_port 5174
11. Start frontend (chemin absolu)
12. Welcome banner
```

## Execution Plan

### Task 1: Ajouter `kill_port()` et `cleanup_stale_pids()`
- **Files**: `shikki` (modify — section Helpers)
- **Implement**: Deux nouvelles fonctions après `is_running()`
- **Verify**: `bash -n shikki` → pas d'erreur de syntaxe
- **BRs**: BR-01, BR-02, BR-05
- **Time**: ~2 min

### Task 2: Améliorer `is_running()` avec vérification port
- **Files**: `shikki` (modify — `is_running()`)
- **Implement**: Vérifier PID existe ET que le port attendu est occupé par ce PID
- **Verify**: Lancer avec PID stale → détecté comme non-running
- **BRs**: BR-05
- **Time**: ~3 min

### Task 3: Guard idempotent dans `do_init()`
- **Files**: `shikki` (modify — début de `do_init()`)
- **Implement**: Si `is_initialized` et pas `--force`, afficher message et exit. Si `--force` ou services running, appeler `do_stop` d'abord.
- **Verify**: `./shikki init` sur workspace initialisé → message propre. `./shikki init --force` → re-init complète.
- **BRs**: BR-03, BR-04
- **Time**: ~3 min

### Task 4: Kill ports avant démarrage dans `do_init()` et `do_start()`
- **Files**: `shikki` (modify — `do_init()` et `do_start()`)
- **Implement**: Appeler `kill_port 3900` avant backend et `kill_port 5174` avant frontend
- **Verify**: Occuper port 3900 avec `nc -l 3900 &`, puis `./shikki start` → démarre sans crash
- **BRs**: BR-01, BR-02
- **Time**: ~3 min

### Task 5: Skip docker containers déjà healthy
- **Files**: `shikki` (modify — docker sections dans `do_init()` et `do_start()`)
- **Implement**: Vérifier `docker compose ps <service>` avant `up -d`. Skip si running+healthy.
- **Verify**: Avec containers running, `./shikki init --force` → pas de "Recreate"
- **BRs**: BR-07
- **Time**: ~5 min

### Task 6: Chemins absolus pour backend et frontend
- **Files**: `shikki` (modify — sections backend/frontend dans `do_init()` et `do_start()`)
- **Implement**: Utiliser `$SCRIPT_DIR/src/backend/src/server.ts` et `cd "$SCRIPT_DIR/src/frontend"`
- **Verify**: `bash -n shikki` + `./shikki init --force` démarre backend correctement
- **BRs**: BR-08, BR-09
- **Time**: ~2 min

### Task 7: Fix routing `status` vs `health`
- **Files**: `shikki` (modify — case routing en bas)
- **Implement**: `status) do_status ;;` et `health) do_health "${2:-}" ;;`
- **Verify**: `./shikki status` affiche projets. `./shikki health` affiche rapport JSON.
- **BRs**: BR-10, BR-11
- **Time**: ~1 min

### Task 8: Trap EXIT + messages d'erreur uniformes
- **Files**: `shikki` (modify — après `set -e`, et messages d'erreur)
- **Implement**: `trap cleanup EXIT` avec fonction qui nettoie PIDs orphelins. Messages d'erreur uniformes pointant vers les logs.
- **Verify**: `Ctrl+C` pendant init → pas de PID stale restant
- **BRs**: BR-12, BR-13
- **Time**: ~3 min

### Task 9: Mettre à jour le help et l'argument parsing pour --force
- **Files**: `shikki` (modify — `do_help()` et case parsing)
- **Implement**: Ajouter `--force` dans l'aide et parser `init --force` correctement
- **Verify**: `./shikki -h` montre l'option --force. `./shikki init --force` fonctionne.
- **BRs**: BR-04
- **Time**: ~2 min

## Implementation Readiness Gate

| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 13/13 BRs mappés à des tasks |
| Test Coverage | PASS | 6/6 scénarios couverts par les tasks |
| File Alignment | PASS | 1 fichier (`shikki`) — couvert par toutes les tasks |
| Task Dependencies | PASS | Tasks 1-2 d'abord (helpers), puis 3-8 (consommateurs), 9 dernier |
| Task Granularity | PASS | Toutes les tasks 1-5 min |
| Testability | PASS | Chaque task a un verify step |

**Verdict: PASS** — prêt pour Phase 6.

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-04-01 | Phase 1-5b | @Sensei | APPROVED | Diagnostic live + spec en une session |
