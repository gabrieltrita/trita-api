#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  sudo=""
else
  sudo="sudo"
fi

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | $sudo sh
fi

if [ -n "$sudo" ]; then
  $sudo usermod -aG docker "$(id -un)"
fi

for port in 80 443; do
  if ! $sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
    $sudo iptables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT
  fi
done

if command -v netfilter-persistent >/dev/null 2>&1; then
  $sudo netfilter-persistent save
fi
