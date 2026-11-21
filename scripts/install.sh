#!/usr/bin/env bash
# Install Docker if needed and start the shared homelab stack from .env.
# Safe to run again. Does not delete /srv/data and does not run "docker compose down -v".
# Does not install a desktop and does not move Docker's data-root.

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo ./scripts/install.sh"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
COMPOSE_DIR="${ROOT_DIR}/compose"
RULES_SCRIPT="${ROOT_DIR}/scripts/docker-user-rules.sh"
BACKUP_SCRIPT="${ROOT_DIR}/scripts/backup-postgres.sh"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing .env. Copy .env.example to .env and set the passwords."
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

require_secret() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "${value}" || "${value}" == "change-me" ]]; then
    echo "${name} is still empty or change-me in .env."
    exit 1
  fi
}

require_secret POSTGRES_PASSWORD
require_secret REDIS_PASSWORD
require_secret MINIO_ROOT_PASSWORD
require_secret GRAFANA_ADMIN_PASSWORD

abs_path() {
  local value="$1"
  if [[ "${value}" == /* ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${ROOT_DIR}/${value#./}"
  fi
}

STORAGE_PATH="$(abs_path "${STORAGE_PATH:-/srv/data}")"
PROJECTS_PATH="$(abs_path "${PROJECTS_PATH:-/srv/projects}")"
BACKUP_PATH="$(abs_path "${BACKUP_PATH:-/srv/backups}")"
if [[ -n "${BACKUP_OFFSITE_PATH:-}" ]]; then
  BACKUP_OFFSITE_PATH="$(abs_path "${BACKUP_OFFSITE_PATH}")"
fi
PUBLIC_HTTP="${PUBLIC_HTTP:-false}"
CADDY_ISSUER="${CADDY_ISSUER:-internal}"
DOMAIN="${DOMAIN:-localhost}"
ACME_EMAIL="${ACME_EMAIL:-admin@localhost}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
PORTAINER_HTTP_PORT="${PORTAINER_HTTP_PORT:-9443}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-homelab}"
ENABLE_BACKUP_TIMER="${ENABLE_BACKUP_TIMER:-false}"

if [[ "${PUBLIC_HTTP}" == "true" ]]; then
  if [[ -z "${DOMAIN}" || "${DOMAIN}" == "localhost" ]]; then
    echo "PUBLIC_HTTP=true requires DOMAIN to be a real hostname."
    exit 1
  fi
  if [[ -z "${ACME_EMAIL}" || "${ACME_EMAIL}" == "admin@localhost" ]]; then
    echo "PUBLIC_HTTP=true requires a real ACME_EMAIL."
    exit 1
  fi
  if [[ "${CADDY_ISSUER}" == "internal" ]]; then
    echo "PUBLIC_HTTP=true requires CADDY_ISSUER=acme."
    exit 1
  fi
fi

if [[ ! -d /run/systemd/system ]]; then
  echo "systemd is required."
  exit 1
fi

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return 0
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
  fi
  if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "Docker is missing, and automatic install supports Ubuntu only."
    exit 1
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

prepare_dirs() {
  local path
  for path in \
    "${STORAGE_PATH}/caddy/data" \
    "${STORAGE_PATH}/caddy/config" \
    "${STORAGE_PATH}/postgres" \
    "${STORAGE_PATH}/redis" \
    "${STORAGE_PATH}/minio" \
    "${STORAGE_PATH}/grafana" \
    "${STORAGE_PATH}/prometheus" \
    "${STORAGE_PATH}/loki" \
    "${STORAGE_PATH}/portainer" \
    "${STORAGE_PATH}/uptime-kuma" \
    "${BACKUP_PATH}/postgres" \
    "${PROJECTS_PATH}"
  do
    mkdir -p "${path}"
  done

  # Numeric ids match the users inside the official images.
  chown -R 0:0 "${STORAGE_PATH}/caddy" "${STORAGE_PATH}/minio" "${STORAGE_PATH}/portainer"
  chown -R 999:999 "${STORAGE_PATH}/postgres" "${STORAGE_PATH}/redis"
  chown -R 472:472 "${STORAGE_PATH}/grafana"
  chown -R 65534:65534 "${STORAGE_PATH}/prometheus"
  chown -R 10001:10001 "${STORAGE_PATH}/loki"
  chown -R 1000:1000 "${STORAGE_PATH}/uptime-kuma"

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    usermod -aG docker "${SUDO_USER}"
    chown "${SUDO_USER}:${SUDO_USER}" "${PROJECTS_PATH}"
  fi
}

copy_volume_if_empty() {
  local volume_key="$1"
  local dest="$2"
  local candidate found=""

  for candidate in "${COMPOSE_PROJECT_NAME}_${volume_key}" "${volume_key}"; do
    if docker volume inspect "${candidate}" >/dev/null 2>&1; then
      found="${candidate}"
      break
    fi
  done

  if [[ -z "${found}" ]]; then
    return 0
  fi
  if [[ -n "$(find "${dest}" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    echo "Keeping existing files in ${dest}."
    return 0
  fi

  echo "Copying Docker volume ${found} into ${dest}. The old volume is left in place."
  docker run --rm \
    -v "${found}:/from:ro" \
    -v "${dest}:/to" \
    alpine:3.21 \
    cp -a /from/. /to/
}

migrate_volumes() {
  copy_volume_if_empty caddy_data "${STORAGE_PATH}/caddy/data"
  copy_volume_if_empty caddy_config "${STORAGE_PATH}/caddy/config"
  copy_volume_if_empty postgres_data "${STORAGE_PATH}/postgres"
  copy_volume_if_empty redis_data "${STORAGE_PATH}/redis"
  copy_volume_if_empty minio_data "${STORAGE_PATH}/minio"
  copy_volume_if_empty grafana_data "${STORAGE_PATH}/grafana"
  copy_volume_if_empty prometheus_data "${STORAGE_PATH}/prometheus"
  copy_volume_if_empty loki_data "${STORAGE_PATH}/loki"
  copy_volume_if_empty portainer_data "${STORAGE_PATH}/portainer"
  copy_volume_if_empty uptime_kuma_data "${STORAGE_PATH}/uptime-kuma"
}

allow_port_from_private() {
  local port="$1"
  local net
  for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10; do
    ufw allow from "${net}" to any port "${port}" proto tcp
  done
  if ip link show tailscale0 >/dev/null 2>&1; then
    ufw allow in on tailscale0 to any port "${port}" proto tcp
  fi
}

allow_current_ssh() {
  local peer ip
  while read -r peer; do
    [[ -z "${peer}" ]] && continue
    ip="${peer%:*}"
    ip="${ip#[}"
    ip="${ip%]}"
    [[ -z "${ip}" ]] && continue
    ufw allow from "${ip}" to any port 22 proto tcp comment homelab-current-ssh
  done < <(ss -Htn state established sport = :22 2>/dev/null | awk '{print $4}' || true)
}

configure_firewall() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ufw iproute2 iptables
  ufw default deny incoming
  ufw default allow outgoing
  allow_current_ssh
  allow_port_from_private 22
  allow_port_from_private "${PORTAINER_HTTP_PORT}"
  allow_port_from_private "${GRAFANA_PORT}"

  ufw --force delete allow 80/tcp >/dev/null 2>&1 || true
  ufw --force delete allow 443/tcp >/dev/null 2>&1 || true
  if [[ "${PUBLIC_HTTP}" == "true" ]]; then
    ufw allow 80/tcp
    ufw allow 443/tcp
  fi

  ufw --force enable
}

configure_tailscale() {
  if [[ -z "${TAILSCALE_AUTHKEY:-}" ]]; then
    echo "TAILSCALE_AUTHKEY is empty. An existing Tailscale login is left as it is."
    return 0
  fi

  if ! command -v tailscale >/dev/null 2>&1; then
    curl -fsSL https://tailscale.com/install.sh | sh
  fi

  if tailscale status >/dev/null 2>&1; then
    echo "Tailscale is already logged in. Leaving it as it is."
    return 0
  fi

  tailscale up --authkey="${TAILSCALE_AUTHKEY}"
}

install_docker_user_unit() {
  cat > /etc/systemd/system/homelab-docker-user.service <<EOF
[Unit]
Description=Limit published homelab container ports
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
Environment=PUBLIC_HTTP=${PUBLIC_HTTP}
ExecStart=${RULES_SCRIPT}
RemainAfterExit=yes

[Install]
WantedBy=docker.service
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable homelab-docker-user.service
}

install_backup_timer() {
  if [[ "${ENABLE_BACKUP_TIMER}" != "true" ]]; then
    if systemctl cat homelab-backup.timer >/dev/null 2>&1; then
      systemctl disable --now homelab-backup.timer || true
    fi
    echo "Backup timer is off. Set ENABLE_BACKUP_TIMER=true to schedule daily dumps."
    return 0
  fi

  cat > /etc/systemd/system/homelab-backup.service <<EOF
[Unit]
Description=Homelab PostgreSQL backup
After=docker.service

[Service]
Type=oneshot
ExecStart=${BACKUP_SCRIPT}
EOF

  cat > /etc/systemd/system/homelab-backup.timer <<EOF
[Unit]
Description=Daily homelab PostgreSQL backup

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=15min

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now homelab-backup.timer
  echo "Daily backup timer is enabled."
}

install_docker
systemctl enable --now docker
prepare_dirs

if [[ -f "${STORAGE_PATH}/postgres/PG_VERSION" ]]; then
  echo "Existing PostgreSQL data found in ${STORAGE_PATH}/postgres."
  echo "Passwords already stored there stay until you rotate them inside Postgres."
  echo "This script will not delete that directory."
fi

cd "${COMPOSE_DIR}"
docker compose --env-file "${ENV_FILE}" stop || true
migrate_volumes
prepare_dirs

configure_tailscale
configure_firewall

docker compose --env-file "${ENV_FILE}" up -d
install_docker_user_unit
"${RULES_SCRIPT}"
install_backup_timer

echo "Shared stack is up. App folders are created by hand under ${PROJECTS_PATH}."
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  echo "Log in again so ${SUDO_USER} can use Docker without sudo."
fi
