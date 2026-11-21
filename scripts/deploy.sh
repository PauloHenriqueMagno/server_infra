#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_DIR="${ROOT_DIR}/compose"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing .env file. Copy .env.example to .env and configure secrets."
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

cd "${COMPOSE_DIR}"

case "${1:-up}" in
  up)
    docker compose --env-file "${ENV_FILE}" pull
    docker compose --env-file "${ENV_FILE}" up -d
    ;;
  down)
    docker compose --env-file "${ENV_FILE}" down
    ;;
  pull)
    docker compose --env-file "${ENV_FILE}" pull
    ;;
  ps)
    docker compose --env-file "${ENV_FILE}" ps
    ;;
  logs)
    shift || true
    docker compose --env-file "${ENV_FILE}" logs -f "$@"
    ;;
  *)
    echo "Usage: $0 {up|down|pull|ps|logs [service]}"
    exit 1
    ;;
esac
