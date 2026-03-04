#!/bin/bash
# ========================================
# Shiki (四季) — Dev OS Workspace
# Single script to launch the full stack
#
# Ports: DB=5433  Ollama=11435  API=3900  UI=5174
#
# Usage:
#   ./start.sh          # start everything
#   ./start.sh stop     # stop everything
#   ./start.sh status   # show running services
# ========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PID_DIR="$SCRIPT_DIR/.pids"
mkdir -p "$PID_DIR"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

# ── Stop ────────────────────────────────────────────────────────────

do_stop() {
  echo -e "${YELLOW}Shutting down Shiki...${NC}"

  # Stop Deno backend
  if [ -f "$PID_DIR/backend.pid" ]; then
    PID=$(cat "$PID_DIR/backend.pid")
    if kill -0 "$PID" 2>/dev/null; then
      echo -e "  Stopping backend (PID $PID)..."
      kill "$PID" 2>/dev/null || true
    fi
    rm -f "$PID_DIR/backend.pid"
  fi

  # Stop Vite frontend
  if [ -f "$PID_DIR/frontend.pid" ]; then
    PID=$(cat "$PID_DIR/frontend.pid")
    if kill -0 "$PID" 2>/dev/null; then
      echo -e "  Stopping frontend (PID $PID)..."
      kill "$PID" 2>/dev/null || true
    fi
    rm -f "$PID_DIR/frontend.pid"
  fi

  # Stop Docker services
  if docker compose ps --quiet 2>/dev/null | grep -q .; then
    echo -e "  Stopping Docker services..."
    docker compose down
  fi

  echo -e "${GREEN}Shiki stopped.${NC}"
}

# ── Status ──────────────────────────────────────────────────────────

do_status() {
  echo -e "${GREEN}四季 Shiki — Status${NC}"
  echo ""

  # Docker
  echo -e "${CYAN}Docker services:${NC}"
  if docker compose ps 2>/dev/null | grep -q "running"; then
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null
  else
    echo -e "  ${DIM}not running${NC}"
  fi
  echo ""

  # Backend
  echo -ne "${CYAN}Backend (port 3900):${NC} "
  if [ -f "$PID_DIR/backend.pid" ] && kill -0 "$(cat "$PID_DIR/backend.pid")" 2>/dev/null; then
    echo -e "${GREEN}running${NC} (PID $(cat "$PID_DIR/backend.pid"))"
  else
    echo -e "${DIM}not running${NC}"
  fi

  # Frontend
  echo -ne "${CYAN}Frontend (port 5174):${NC} "
  if [ -f "$PID_DIR/frontend.pid" ] && kill -0 "$(cat "$PID_DIR/frontend.pid")" 2>/dev/null; then
    echo -e "${GREEN}running${NC} (PID $(cat "$PID_DIR/frontend.pid"))"
  else
    echo -e "${DIM}not running${NC}"
  fi

  # Projects
  echo ""
  echo -e "${CYAN}Projects:${NC}"
  if [ -d "projects" ] && [ "$(ls -A projects/ 2>/dev/null | grep -v '.gitkeep')" ]; then
    for dir in projects/*/; do
      [ -d "$dir" ] && echo -e "  ${GREEN}$(basename "$dir")${NC}"
    done
  else
    echo -e "  ${DIM}none${NC}"
  fi
  echo ""
}

# ── Start ───────────────────────────────────────────────────────────

do_start() {
  echo -e "${GREEN}四季 Shiki — Dev OS Workspace${NC}"
  echo ""

  # ── Prerequisites ──

  local missing=0

  if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker not found.${NC} Install: https://docs.docker.com/get-docker/"
    missing=1
  fi

  if ! command -v deno &> /dev/null; then
    echo -e "${RED}Deno not found.${NC} Install: brew install deno"
    missing=1
  fi

  if ! command -v node &> /dev/null; then
    echo -e "${RED}Node.js not found.${NC} Install: https://nodejs.org"
    missing=1
  fi

  [ $missing -eq 1 ] && exit 1

  # ── Environment ──

  if [ ! -f .env ]; then
    echo -e "${YELLOW}No .env file found — copying from .env.example${NC}"
    cp .env.example .env
    echo -e "${YELLOW}  Edit .env to set POSTGRES_PASSWORD before production use.${NC}"
  fi

  source .env

  # ── Docker services (DB + Ollama) ──

  echo -e "${CYAN}Starting Docker services (PostgreSQL + Ollama)...${NC}"
  docker compose up -d db ollama

  echo -ne "  Waiting for PostgreSQL..."
  for i in $(seq 1 30); do
    if docker compose exec -T db pg_isready -U "${POSTGRES_USER:-acc}" -d "${POSTGRES_DB:-acc}" &>/dev/null; then
      echo -e " ${GREEN}ready${NC}"
      break
    fi
    [ $i -eq 30 ] && { echo -e " ${RED}timeout${NC}"; exit 1; }
    sleep 1
    echo -n "."
  done

  echo -ne "  Waiting for Ollama..."
  for i in $(seq 1 60); do
    if curl -sf http://localhost:11435/api/tags &>/dev/null; then
      echo -e " ${GREEN}ready${NC}"
      break
    fi
    [ $i -eq 60 ] && { echo -e " ${RED}timeout${NC}"; exit 1; }
    sleep 1
    echo -n "."
  done

  # Pull embedding model in background (non-blocking)
  docker compose up -d ollama-init

  # ── Deno backend ──

  echo -e "${CYAN}Starting Deno backend on port 3900...${NC}"

  export DATABASE_URL="postgres://${POSTGRES_USER:-acc}:${POSTGRES_PASSWORD}@localhost:5433/${POSTGRES_DB:-acc}"
  export OLLAMA_URL="http://localhost:11435"
  export EMBED_MODEL="nomic-embed-text"
  export WS_PORT=3900

  cd src/backend
  deno run --allow-net --allow-env --allow-read src/server.ts &
  BACKEND_PID=$!
  echo "$BACKEND_PID" > "$PID_DIR/backend.pid"
  cd "$SCRIPT_DIR"

  sleep 1

  if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
    echo -e "${RED}Backend failed to start.${NC}"
    exit 1
  fi

  # ── Vue frontend ──

  echo -e "${CYAN}Starting Vue frontend on port 5174...${NC}"

  cd src/frontend
  if [ ! -d "node_modules" ]; then
    echo -e "  ${DIM}Installing npm dependencies...${NC}"
    npm install --silent
  fi
  npx vite --port 5174 --host &
  FRONTEND_PID=$!
  echo "$FRONTEND_PID" > "$PID_DIR/frontend.pid"
  cd "$SCRIPT_DIR"

  sleep 1

  # ── Ready ──

  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  四季 Shiki is running${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  Dashboard:  ${CYAN}http://localhost:5174${NC}"
  echo -e "  API:        ${CYAN}http://localhost:3900${NC}"
  echo -e "  WebSocket:  ${CYAN}ws://localhost:3900/ws${NC}"
  echo -e "  Health:     ${CYAN}http://localhost:3900/health${NC}"
  echo -e "  PostgreSQL: ${DIM}localhost:5433${NC}"
  echo -e "  Ollama:     ${DIM}localhost:11435${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "${DIM}Press Ctrl+C to stop all services${NC}"

  # ── Trap & wait ──

  cleanup() {
    echo ""
    do_stop
  }
  trap cleanup INT TERM

  # Wait for any child to exit
  wait
}

# ── Main ────────────────────────────────────────────────────────────

case "${1:-start}" in
  start)   do_start ;;
  stop)    do_stop ;;
  status)  do_status ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac
