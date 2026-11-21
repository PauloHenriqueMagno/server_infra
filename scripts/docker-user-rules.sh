#!/usr/bin/env bash
# Keep published container ports off the public internet.
# Docker bypasses UFW, so these rules live on the DOCKER-USER chain.
# Private addresses and Tailscale can still reach the published ports.
# Ports 80 and 443 are allowed from anywhere only when PUBLIC_HTTP=true.

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo ./scripts/docker-user-rules.sh"
  exit 1
fi

PUBLIC_HTTP="${PUBLIC_HTTP:-false}"

apply_rules() {
  local cmd="$1"
  local chain="$2"

  if ! "${cmd}" -nL DOCKER-USER >/dev/null 2>&1; then
    echo "${cmd}: DOCKER-USER is not present yet."
    return 0
  fi

  "${cmd}" -N "${chain}" 2>/dev/null || "${cmd}" -F "${chain}"
  if ! "${cmd}" -C DOCKER-USER -j "${chain}" >/dev/null 2>&1; then
    "${cmd}" -I DOCKER-USER 1 -j "${chain}"
  fi

  "${cmd}" -A "${chain}" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
  "${cmd}" -A "${chain}" -i lo -j RETURN
  "${cmd}" -A "${chain}" -i docker0 -j RETURN
  "${cmd}" -A "${chain}" -i br-+ -j RETURN
  "${cmd}" -A "${chain}" -i tailscale0 -j RETURN

  if [[ "${cmd}" == "iptables" ]]; then
    "${cmd}" -A "${chain}" -s 10.0.0.0/8 -j RETURN
    "${cmd}" -A "${chain}" -s 172.16.0.0/12 -j RETURN
    "${cmd}" -A "${chain}" -s 192.168.0.0/16 -j RETURN
    "${cmd}" -A "${chain}" -s 100.64.0.0/10 -j RETURN
  else
    "${cmd}" -A "${chain}" -s fc00::/7 -j RETURN
  fi

  if [[ "${PUBLIC_HTTP}" == "true" ]]; then
    "${cmd}" -A "${chain}" -p tcp -m multiport --dports 80,443 -j RETURN
  fi

  "${cmd}" -A "${chain}" -j DROP
}

wait_for_chain() {
  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if iptables -nL DOCKER-USER >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "DOCKER-USER did not appear. Docker may not be running."
  return 1
}

wait_for_chain
apply_rules iptables HOMELAB-DOCKER
if ip6tables -nL DOCKER-USER >/dev/null 2>&1; then
  apply_rules ip6tables HOMELAB-DOCKER6
fi

echo "Docker published ports are limited to the LAN, Tailscale, and localhost."
if [[ "${PUBLIC_HTTP}" == "true" ]]; then
  echo "Public HTTP and HTTPS are open."
else
  echo "Public HTTP and HTTPS stay closed."
fi
