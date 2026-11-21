#!/usr/bin/env bash
# Install the Ubuntu graphical session on this machine.
# This script is not called by install.sh. It does not start Docker and it does not create /srv.

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo ./scripts/install-desktop.sh"
  exit 1
fi

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
fi

if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This script installs the Ubuntu desktop. ${ID:-unknown} is not supported."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ubuntu-desktop-minimal

systemctl set-default graphical.target
if [[ -f /lib/systemd/system/gdm3.service || -f /usr/lib/systemd/system/gdm3.service ]]; then
  systemctl enable gdm3.service
fi

echo "Ubuntu desktop is installed. The graphical login is the default on the next boot."
echo "This script does not start Docker and does not change /srv."
