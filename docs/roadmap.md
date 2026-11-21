# Homelab roadmap

`install.sh` is the server bootstrap. You clone this repo on the Ubuntu host, edit `.env`, and run it with admin rights. It installs Docker if needed and starts the shared platform already configured in this repo: Caddy, Postgres, Redis, MinIO, Portainer, Grafana, Prometheus, Loki, Promtail, node-exporter, cAdvisor, and Uptime Kuma. Those services are shared production infrastructure. Apps use them. They are not split into a dev copy and a demo copy.

A daily wipe belongs to a demo project, inside that project's repository. It drops and recreates that project's database, clears that project's uploads, then migrates and seeds. The shared Postgres data, other databases, MinIO data for other projects, and Portainer stay in place.

## How you run it

```bash
git clone <this-repo> /srv/infra
cd /srv/infra
cp .env.example .env
# edit passwords, STORAGE_PATH, PROJECTS_PATH, BACKUP_PATH, domain
sudo ./scripts/install.sh
```

`scripts/install.sh`:

- Exits unless it is root (`sudo`).
- Exits if `.env` is missing or a password is still `change-me`.
- Reads `.env` and is safe to run again after you change a path, domain, or `PUBLIC_HTTP`.
- Installs Docker Engine and the Compose plugin when they are absent.
- Creates one data directory per shared service, plus a single projects directory and the backup directory. It does not create app folders.
- Starts the full shared Compose stack. Compose bind-mounts those data directories.
- Applies UFW. SSH, Portainer, and Grafana are allowed from the LAN and from the Tailscale interface. Ports 80 and 443 are allowed on the public interface only when `PUBLIC_HTTP=true`. Postgres, Redis, and MinIO listen on `127.0.0.1` only, so a client on another computer reaches them through an SSH tunnel.
- Does not run `docker compose down -v` and does not delete `/srv/data`. If a named volume from an older install still exists and the new directory is empty, the script copies that volume in before switching. An existing Tailscale login is left as it is when `TAILSCALE_AUTHKEY` is empty.
- Installs the daily backup timer when `ENABLE_BACKUP_TIMER=true`.
- Joins Tailscale when `TAILSCALE_AUTHKEY` is set.

There is no demo-reset flag. The wipe script is not installed here. `install.sh` does not install a desktop. It does not move Docker's data-root.

## Desktop is a second script

Use a separate script so a headless machine, or another computer, can run the infra again without installing a GUI. `install.sh` never calls it. Either script can be run alone, and either can be run again.

```bash
sudo ./scripts/install-desktop.sh
```

`scripts/install-desktop.sh`:

- Exits unless it is root.
- Installs `ubuntu-desktop-minimal` with apt and enables the graphical login.
- Does not read service passwords, start Docker, or create `/srv/data` or `/srv/projects`.
- Is safe to run again. A second run leaves an existing desktop in place.
- Does not install a virtual machine, NoMachine, or RDP.

On the 16 GB server you can skip it and keep that host for containers. On a computer you sit at, run it before or after `install.sh`. Moving the platform to another computer is another clone, another `.env`, and `sudo ./scripts/install.sh` only.

`scripts/deploy.sh` stays the day-to-day control (`ps`, `logs`, `pull`, `up`) and reads the same `.env`. A second `install.sh` run updates containers to match the repo. Database passwords already stored in the Postgres directory stay until a separate rotate step. The script says so and leaves the data directory in place.

## Folders

`install.sh` creates the service directories and one empty `projects` folder. App names such as `ToDoApp`, `ToDoApp2Teste`, and `ToDoApp2Prod` are directories you add by hand under `projects/`.

```
/srv/
├── infra/                  # this repo
├── projects/               # empty; you mkdir each app here
├── data/
│   ├── caddy/
│   ├── postgres/
│   ├── redis/
│   ├── minio/
│   ├── grafana/
│   ├── prometheus/
│   ├── loki/
│   ├── portainer/
│   └── uptime-kuma/
└── backups/
    └── postgres/
```

node-exporter, cAdvisor, and Promtail start with the same stack. They read the host and the Docker socket, so they do not get a directory under `/srv/data`. Uptime Kuma starts with the stack too. Discord, Telegram, or email alerts are set in its UI, not in `install.sh`.

`.env` knobs:

- `STORAGE_PATH=/srv/data`, `PROJECTS_PATH=/srv/projects`, `BACKUP_PATH=/srv/backups`, plus the service passwords.
- `PUBLIC_HTTP=false` until a domain and the CGNAT check are done.
- `ACME_EMAIL`, `DOMAIN`, and `CADDY_ISSUER` for Caddy. `CADDY_ISSUER=internal` until public HTTPS, then `acme`.
- `ENABLE_BACKUP_TIMER=false` until you want the daily timer. `BACKUP_OFFSITE_PATH` is the directory on a disk that is not the NVMe.
- `TAILSCALE_AUTHKEY` empty unless this host still needs to join.

## Decisions

- This repo is the shared platform. Application source and the daily wipe script stay in each app repo.
- One Postgres, one Redis, one MinIO, each with its own directory under `/srv/data`. Each app gets its own database, database user, and object prefix.
- One `/srv/projects` directory. You create each app folder yourself. The install script does not split projects into dev, prod, and demo trees.
- A demo project's wipe script names that project's database and prefix. It runs migrations and seeds afterward. It does not remove the shared Postgres, Redis, or MinIO directories, and it does not call `docker system prune`.
- Remote development is a normal SSH login to `/srv/projects/<app>`. The server does not care which IDE opens that session. Cursor, VS Code, JetBrains, Zed, and a plain terminal all work. Xcode stays on the Mac for iOS. Work and personal projects can use different IDEs against the same host.
- The Ubuntu desktop is `scripts/install-desktop.sh` on the machines that need a local GUI. code-server and Cockpit stay optional.
- The machine this roadmap is sized for is the existing host: Ryzen 5, 6 cores, 16 GB RAM, a 110 GB SATA SSD for Ubuntu, and a 1 TB NVMe for `/srv`.
- Host data lives on the NVMe under `/srv`. The git checkout is configuration only. No container memory limits are set on the first install.
- Portainer and Grafana are reachable on the LAN and over Tailscale, from any of your computers. Caddy's 80/443 face the internet only after `PUBLIC_HTTP=true`. Databases and MinIO stay on the Docker network, with a `127.0.0.1` port for SSH tunnels.
- This repo does not build app images. Each app keeps its own Dockerfile and CI.

## Phase 0 — Read the server, change nothing

Run on the Ubuntu host before the first install.

- OS and kernel: `lsb_release -a`, `uname -r`
- CPU, RAM, disks: `lscpu`, `free -h`, `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL`, `df -hT`
- Docker, if present: `docker ps -a`, `docker volume ls`, `docker info -f '{{.DockerRootDir}}'`
- Addresses: `ip -br addr`
- Tailscale: `tailscale status`

Use that note to see which disk is `/`, which is the NVMe, whether Docker's data-root is on the small SSD, whether Tailscale is already logged in, and which containers and named volumes already exist. No partitions or volumes move in this phase. The first `install.sh` copies an existing named volume into `/srv/data/<service>` when that directory is still empty.

## Phase 1 — Install the shared stack

- Clone to `/srv/infra`, copy `.env.example` to `.env`, set passwords, `STORAGE_PATH=/srv/data`, `PROJECTS_PATH=/srv/projects`, and `BACKUP_PATH=/srv/backups`.
- Leave `PUBLIC_HTTP=false`.
- `sudo ./scripts/install.sh` creates `/srv/data/<service>`, `/srv/projects`, and `/srv/backups/postgres`.

Exit: the shared services are running, each storing data in its own folder. `/srv/projects` exists and is empty. Postgres, Redis, and MinIO are the shared instances apps will use.

## Phase 2 — Keep shared data off the public interface

This is already how `install.sh` starts the stack.

- One Docker network, `infra`. Apps join it.
- Postgres, Redis, and MinIO bind to `127.0.0.1` only. Apps reach them by container name (`postgres`, `redis`, `minio`). A client on another computer uses an SSH tunnel.
- Persistent data uses the `/srv/data/<service>` bind mounts. A re-run does not delete those directories.
- Caddy hostnames, the ACME email, and the certificate issuer come from `.env`. The Caddyfile in git stays the configuration.

Exit: from another machine on the internet, port 5432 does not answer.

## Phase 3 — Admin access

Set `TAILSCALE_AUTHKEY` only if this host still needs to join, keep `PUBLIC_HTTP=false`, and re-run `sudo ./scripts/install.sh`.

- UFW allows SSH, Portainer, and Grafana from the LAN and from Tailscale, and leaves 80/443 closed on the public interface while `PUBLIC_HTTP=false`.
- Docker's own firewall rules are adjusted so published container ports are not reachable from the public internet. Private addresses and Tailscale still can reach them.
- The script leaves SSH password login as it found it, so a bad run cannot lock you out. Turn password login off manually after a key session works.
- With Tailscale disconnected, the next admin login is on the LAN.

Exit: from any of your computers, over Tailscale, SSH and Portainer work. Those ports do not answer from the public internet.

## Phase 4 — Apps on the shared services

- Each app is a directory you create under `/srv/projects`, for example `/srv/projects/ToDoApp` and `/srv/projects/ToDoApp2Teste`. Its Compose file joins the `infra` network.
- On first deploy the app creates its database and user on the shared Postgres, and its prefix on MinIO.
- You SSH in from whichever IDE you use for that project and open `/srv/projects/<app>` on the server. The browser reaches the app through Tailscale or Caddy.
- Connection names are `postgres`, `redis`, and `minio`. Each app owns one database.

Exit: one app runs on the server against the shared Postgres.

## Phase 5 — Daily wipe, inside the demo project

This repo does not ship the wipe.

- The demo project's repository contains `reset.sh` and a systemd unit, or a cron entry, on the server. A failed run is visible in the journal. The script does not call `docker system prune`.
- The script stops that project's app containers, drops and recreates only that project's database, deletes uploads inside that project's directory (for example `/srv/projects/ToDoApp2Teste`), starts the app, runs its migrations and seeds, and checks its health URL. Sibling folders such as `/srv/projects/ToDoApp2Prod` stay untouched.
- A trial run while a second database exists leaves that second database and its rows in place.

Exit: the demo project returns to seed data on a schedule, and another project's database is unchanged.

## Phase 6 — First public site

After a CGNAT check (`curl -4 ifconfig.me` compared with the router):

- Public IPv4: set `PUBLIC_HTTP=true`, `ACME_EMAIL`, `DOMAIN`, and `CADDY_ISSUER=acme`, re-run `sudo ./scripts/install.sh`, and forward 80/443 on the router.
- CGNAT: leave `PUBLIC_HTTP=false` and point a Cloudflare Tunnel, or a small VPS, at Caddy.

Publish a disposable app before any real data.

Exit: `https://` works for the test hostname. Portainer stays on Tailscale.

## Phase 7 — Backups of the shared data

- Set `ENABLE_BACKUP_TIMER=true` and `BACKUP_OFFSITE_PATH` to a directory on a disk that is not the NVMe, then re-run `sudo ./scripts/install.sh`.
- The timer dumps the shared Postgres. The dump includes every database on that instance. Demo databases are recreated by the project wipe, so they do not need a long retention of their own.
- Local retention is 7 daily dumps. When `BACKUP_OFFSITE_PATH` is set, the script also keeps 7 daily copies and 4 weekly copies there.
- Restore one real project's database onto a scratch database name before that project holds data you care about.

Exit: yesterday's dump of a real project restores, and the backup files are off the NVMe.

## Explicitly later

code-server, Cockpit, Authentik or Keycloak, Kubernetes, a second server, separate database servers per environment, and a remote-desktop server (RDP or NoMachine) on top of the desktop script. Revisit a RAM upgrade to 32 GB if the shared stack, the apps, and a local desktop crowd the 16 GB host.
