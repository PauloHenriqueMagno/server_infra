#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing .env file."
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

abs_path() {
  local value="$1"
  if [[ "${value}" == /* ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${ROOT_DIR}/${value#./}"
  fi
}

BACKUP_PATH="$(abs_path "${BACKUP_PATH:-backups}")"
BACKUP_DIR="${BACKUP_PATH}/postgres"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/postgres_${TIMESTAMP}.sql.gz"

mkdir -p "${BACKUP_DIR}"

docker exec postgres pg_dumpall -U "${POSTGRES_USER}" | gzip > "${BACKUP_FILE}"

echo "Backup saved to ${BACKUP_FILE}"

# Keep last 7 daily backups in BACKUP_PATH.
prune_dumps() {
  local dir="$1"
  local keep="$2"
  find "${dir}" -name "postgres_*.sql.gz" -type f | sort -r | tail -n +"$((keep + 1))" | xargs -r rm --
}

prune_dumps "${BACKUP_DIR}" 7

# Off-NVMe copy. 7 daily and 4 weekly, only when BACKUP_OFFSITE_PATH is set.
if [[ -n "${BACKUP_OFFSITE_PATH:-}" ]]; then
  BACKUP_OFFSITE_PATH="$(abs_path "${BACKUP_OFFSITE_PATH}")"
  mkdir -p "${BACKUP_OFFSITE_PATH}/daily" "${BACKUP_OFFSITE_PATH}/weekly"
  cp -a "${BACKUP_FILE}" "${BACKUP_OFFSITE_PATH}/daily/"
  prune_dumps "${BACKUP_OFFSITE_PATH}/daily" 7
  if [[ "$(date +%u)" -eq 7 ]]; then
    cp -a "${BACKUP_FILE}" "${BACKUP_OFFSITE_PATH}/weekly/"
    prune_dumps "${BACKUP_OFFSITE_PATH}/weekly" 4
  fi
  echo "Off-site copy saved under ${BACKUP_OFFSITE_PATH}"
fi
