#!/usr/bin/env bash
# Install the free NoMachine server so a client can open this machine's desktop.
# This script is not called by install.sh or install-desktop.sh.
# It does not start Docker and it does not change /srv.
#
# NoMachine no longer publishes the free 8.28.2 package. 9.8.2 is the last
# build whose package name is "nomachine" and which does not ask for a
# subscription. Version 10 packages are left unused.

set -euo pipefail

NOMACHINE_URL="https://apt.iteas.at/iteas/pool/main/n/nomachine/nomachine_9.8.2_1_amd64.deb"
NOMACHINE_MD5="29f24af614a1cd3da4e69c407fe31b2a"
NOMACHINE_PORT=4000

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo ./scripts/install-nomachine.sh"
  exit 1
fi

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
fi

if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This script installs NoMachine on Ubuntu. ${ID:-unknown} is not supported."
  exit 1
fi

allow_port_from_private() {
  local port="$1"
  local proto="$2"
  local net
  for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10; do
    ufw allow from "${net}" to any port "${port}" proto "${proto}"
  done
  if ip link show tailscale0 >/dev/null 2>&1; then
    ufw allow in on tailscale0 to any port "${port}" proto "${proto}"
  fi
}

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ufw ca-certificates curl

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
deb="${workdir}/nomachine_9.8.2_1_amd64.deb"
curl -fL --retry 3 -o "${deb}" "${NOMACHINE_URL}"

actual_md5="$(md5sum "${deb}" | awk '{print $1}')"
if [[ "${actual_md5}" != "${NOMACHINE_MD5}" ]]; then
  echo "NoMachine download checksum does not match. Nothing was installed."
  exit 1
fi

package_name="$(dpkg-deb -f "${deb}" Package)"
if [[ "${package_name}" != "nomachine" ]]; then
  echo "Refusing to install package ${package_name}. Only the free nomachine package is accepted."
  exit 1
fi

dpkg -i "${deb}" || apt-get install -y -f

allow_port_from_private "${NOMACHINE_PORT}" tcp
allow_port_from_private "${NOMACHINE_PORT}" udp

systemctl enable nxserver
systemctl restart nxserver

echo "NoMachine is listening on port ${NOMACHINE_PORT} for the private network and Tailscale."
echo "Sign in as the Linux user. This script does not start Docker and does not change /srv."
