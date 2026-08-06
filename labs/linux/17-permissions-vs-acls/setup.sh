#!/usr/bin/env bash
# Lab 29 setup — build a permissions incident that plain chmod/chown
# genuinely cannot solve cleanly: a shared directory that two unrelated
# groups both need to write to, without loosening it to everyone.
set -euo pipefail

echo "[setup] installing acl tools if missing..."
if ! command -v setfacl >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq acl
fi

echo "[setup] creating two unrelated teams..."
sudo groupadd -f teamA
sudo groupadd -f teamB
sudo useradd -m -g teamA alice 2>/dev/null || true
sudo useradd -m -g teamB bob 2>/dev/null || true

echo "[setup] creating a shared directory owned by teamA only..."
sudo mkdir -p /srv/shared
sudo chown root:teamA /srv/shared
sudo chmod 770 /srv/shared

echo "[setup] alice (teamA) writes a file into it, as the normal case..."
sudo -u alice touch /srv/shared/alice_file.txt

echo "[setup] current state:"
ls -ld /srv/shared
ls -l /srv/shared

echo "[setup] confirming bob (teamB) is locked out:"
if sudo -u bob touch /srv/shared/bob_file.txt 2>/var/tmp/lab29-bob.err; then
  echo "[setup] unexpected: bob could write already"
else
  cat /var/tmp/lab29-bob.err
fi

echo "[setup] done. bob needs write access too, WITHOUT loosening this to"
echo "[setup] everyone and without merging teamA/teamB. Standard chmod/chown"
echo "[setup] can't express 'two specific groups, nobody else' — that's the"
echo "[setup] point of this lab."
