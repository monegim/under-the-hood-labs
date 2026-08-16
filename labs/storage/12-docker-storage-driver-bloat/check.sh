#!/usr/bin/env bash
# Lab 12 check — verifies the SAFE, incremental reclaim from Step 5 was
# done correctly: dangling images and stopped containers are gone, but
# tagged images and named volumes (which only die to -a/--volumes,
# covered as exploration in the challenges, not as "the fix") are
# untouched.
set -uo pipefail

PASS=0
SOCK=/var/run/dockerlab.sock
DOCKER="sudo docker -H unix://$SOCK"

echo "[check] is the lab dockerd reachable?"
if ! $DOCKER info >/dev/null 2>&1; then
    echo "[FAIL] lab dockerd on $SOCK is not reachable — run setup.sh first."
    exit 1
fi

echo "[check] any stopped containers left (container prune should have removed them)?"
STOPPED=$($DOCKER ps -a -f status=exited -q | wc -l | tr -d ' ')
echo "[check] stopped container count: $STOPPED"
if [ "$STOPPED" -ne 0 ]; then
    echo "[FAIL] $STOPPED stopped container(s) remain — container prune wasn't run, or didn't finish."
    PASS=1
fi

echo "[check] any dangling images left (image prune should have removed them)?"
DANGLING=$($DOCKER images -f dangling=true -q | wc -l | tr -d ' ')
echo "[check] dangling image count: $DANGLING"
if [ "$DANGLING" -ne 0 ]; then
    echo "[FAIL] $DANGLING dangling image(s) remain — image prune wasn't run, or didn't finish."
    PASS=1
fi

echo "[check] is the tagged myapp:latest image still present (a safe prune must not remove it)?"
if $DOCKER images myapp:latest -q | grep -q .; then
    echo "[check] myapp:latest is present, as expected."
else
    echo "[FAIL] myapp:latest is gone — something removed a tagged image, which plain 'image prune' (no -a) never should."
    PASS=1
fi

echo "[check] are both named volumes still present (a safe prune must not touch volumes)?"
for v in dockerlab_appdata dockerlab_orphaned_logs; do
    if $DOCKER volume inspect "$v" >/dev/null 2>&1; then
        echo "[check] volume $v is present, as expected."
    else
        echo "[FAIL] volume $v is gone — nothing in the safe reclaim path (Step 5) should ever remove a volume."
        PASS=1
    fi
done

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] safe reclaim done correctly: dangling images and stopped containers gone, tagged image and volumes untouched."
    exit 0
else
    echo "[FAIL] see details above."
    exit 1
fi
