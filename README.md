# Homelab Infrastructure

> Infrastructure as Code repository for my self-hosted platform.

## Goals

- Infrastructure managed through Git.
- Every service runs in Docker.
- Applications are independent from infrastructure.
- GitHub Actions builds application images.
- The server only pulls and runs images.
- One-command disaster recovery.

---

# Architecture

```
GitHub Actions
        │
        ▼
GitHub Container Registry (GHCR)
        │
        ▼
Home Server
        │
        ├── Reverse Proxy
        ├── Infrastructure Services
        ├── Application Services
        └── Persistent Storage
```

---

# Repository Structure

```
homelab-infra/

├── compose/
│   ├── caddy/
│   ├── postgres/
│   ├── redis/
│   ├── object-storage/
│   ├── grafana/
│   ├── prometheus/
│   ├── loki/
│   ├── portainer/
│   └── uptime-kuma/
│
├── configs/
│
├── storage/
│
├── scripts/
│
├── backups/
│
└── docs/
    └── roadmap.md
```

Server data is not stored in this checkout. `scripts/install.sh` creates `/srv/data`, `/srv/projects`, and `/srv/backups` on the host.

---

# Infrastructure Services

## Reverse Proxy

Purpose

- Public HTTPS
- Automatic TLS certificates
- Reverse proxy
- HTTP → HTTPS redirect

Technology

- Caddy

---

## PostgreSQL

Purpose

- Primary relational database
- Multiple databases
- Daily backups

Requirements

- Persistent volume
- Health checks
- Automated backup

---

## Redis

Purpose

- Cache
- Queues
- Session storage

Requirements

- Persistent storage
- Password protected

---

## Object Storage

Purpose

- User uploads
- Images
- Documents
- Static assets
- Application backups

Preferred

- MinIO Community Edition

Alternative

- SeaweedFS

Requirements

- S3 compatible
- Persistent storage
- Versioning
- Backup support

---

## Grafana

Purpose

- Dashboards
- Infrastructure visualization

Data Sources

- Prometheus
- Loki

---

## Prometheus

Purpose

- Metrics collection

Collect

- CPU
- RAM
- Disk
- Docker
- Containers
- Network

---

## Loki

Purpose

- Centralized logs

Sources

- Docker containers
- System logs

---

## Uptime Kuma

Purpose

- Service monitoring

Checks

- HTTP
- HTTPS
- TCP
- Docker services

Notifications

- Discord
- Telegram
- Email

---

## Portainer

Purpose

- Docker management
- Container logs
- Volume management

Used only for visualization and troubleshooting.

Infrastructure changes should always be performed through Git.

---

# Applications

Applications are **not stored** in this repository.

Each application owns:

- source code
- Dockerfile
- GitHub Actions workflow

Deployment target:

```
ghcr.io/<user>/<application>
```

---

# Deployment Flow

```
git push
        │
        ▼
GitHub Actions

Run Tests

        ▼

Build Docker Image

        ▼

Push to GHCR

        ▼

Notify Home Server

        ▼

docker compose pull

        ▼

docker compose up -d

        ▼

Health Check
```

---

# Disaster Recovery

New Server

1. Install Ubuntu Server.
2. Install Docker.
3. Clone homelab-infra.
4. Configure secrets.
5. Start infrastructure.
6. Restore backups.
7. Applications automatically pull their images from GHCR.

Target recovery time: under 30 minutes.

---

# Future Improvements

- Secret management
- GitOps
- Automatic backups
- VPN access
- Object storage replication
- Multi-server cluster
- Kubernetes (k3s)
- Continuous security scanning
- Automatic image updates
- Infrastructure tests
- Blue/Green deployments
- Zero-downtime deployments
- Identity Provider (Authentik or Keycloak)
- Centralized authentication
- Service mesh (future)

---

# Quick Start

## Image Catalog

All infrastructure images and pinned versions are defined in [`images.yaml`](images.yaml):

| Service | Image | Version |
|---------|-------|---------|
| Caddy | `caddy` | 2.9.1-alpine |
| PostgreSQL | `postgres` | 17.5-alpine |
| Redis | `redis` | 7.4.2-alpine |
| MinIO | `minio/minio` | RELEASE.2025-04-22T22-12-26Z |
| Grafana | `grafana/grafana` | 11.6.0 |
| Prometheus | `prom/prometheus` | v3.2.1 |
| Node Exporter | `prom/node-exporter` | v1.9.0 |
| cAdvisor | `gcr.io/cadvisor/cadvisor` | v0.51.0 |
| Loki | `grafana/loki` | 3.4.2 |
| Promtail | `grafana/promtail` | 3.4.2 |
| Portainer | `portainer/portainer-ce` | 2.27.1 |
| Uptime Kuma | `louislam/uptime-kuma` | 1.23.16 |

When upgrading a service, update both `images.yaml` and `.env.example`, then run `sudo ./scripts/install.sh` again.

## Install

On the Ubuntu host, clone this repo, edit `.env`, and run the admin script. It installs Docker when it is missing and starts the shared stack. Configurations for Caddy, Prometheus, Loki, and Grafana stay in this repo. The only file you edit on the server is `.env`.

```bash
git clone <this-repo> /srv/infra
cd /srv/infra
cp .env.example .env
# passwords, STORAGE_PATH, PROJECTS_PATH, BACKUP_PATH, domain

sudo ./scripts/install.sh
```

A local graphical session is a separate script. It does not start Docker or create `/srv`. Skip it on a machine that should only host containers. Run it on a machine you sit at.

```bash
sudo ./scripts/install-desktop.sh
```

Either script can be run on its own, and either can be run again. Moving the platform to another computer is a new clone, a new `.env`, and `sudo ./scripts/install.sh` only.

Phases, firewall behavior, and the project layout are in [`docs/roadmap.md`](docs/roadmap.md).

## Day-to-day Compose

```bash
./scripts/deploy.sh ps
./scripts/deploy.sh logs
./scripts/deploy.sh pull
./scripts/deploy.sh up
```

`deploy.sh` reads the same `.env`. The first start on a host is `sudo ./scripts/install.sh`.

## Daily PostgreSQL Backup

```bash
./scripts/backup-postgres.sh
```

Dumps are stored in `BACKUP_PATH/postgres` (default `/srv/backups/postgres`) and the last 7 are kept. Set `ENABLE_BACKUP_TIMER=true` and re-run `sudo ./scripts/install.sh` to schedule that script daily. Set `BACKUP_OFFSITE_PATH` to also copy dumps onto a disk that is not the NVMe.
