#!/usr/bin/env bash
# Incident 06 setup - builds the entire broken environment turnkey:
#   postgres      - Postgres 16, one "orders" table.
#   checkout-api  - a Flask Deployment (3 replicas) in front of it.
#
# This deploys checkout-api revision 1 first and *proves* it's serving
# real /checkout requests successfully - so the "before" state is
# genuinely healthy, not broken from line one. It then rolls out
# revision 2, which is the actual incident: a typo'd env var name
# (DB_PASSWROD instead of DB_PASSWORD) means every v2 pod starts with an
# empty DB password, while the readiness/liveness probe never changed
# and never touched Postgres in the first place - so the rollout reports
# success and every pod goes Ready, right before real checkout traffic
# starts failing.
#
# By the time this script finishes, the incident is already live, same
# as walking onto a real page in progress.
set -euo pipefail

CLUSTER="incident06"
CTX="kind-${CLUSTER}"
NS="default"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[1/8] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/8] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/8] Deploying Postgres..."
kubectl --context "${CTX}" apply -f manifests/postgres.yaml
kubectl --context "${CTX}" wait --for=condition=Ready pod -l app=postgres -n "${NS}" --timeout=120s

echo "[4/8] Loading checkout-api's application code as a ConfigMap..."
kubectl --context "${CTX}" create configmap checkout-api-code \
    --from-file=app.py=app/app.py \
    --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -

echo "[5/8] Rolling out checkout-api revision 1 (known-good baseline)..."
kubectl --context "${CTX}" apply -f manifests/checkout-api-v1.yaml
kubectl --context "${CTX}" rollout status deployment/checkout-api -n "${NS}" --timeout=180s

echo "[6/8] Proving v1 actually works - a real /checkout request end to end..."
kubectl --context "${CTX}" delete pod setup-check --ignore-not-found -n "${NS}" >/dev/null 2>&1 || true
PF_PID=""
kubectl --context "${CTX}" port-forward svc/checkout-api 18080:80 -n "${NS}" >/tmp/incident06-pf.log 2>&1 &
PF_PID=$!
sleep 3
V1_RESULT=$(curl -s -X POST http://localhost:18080/checkout -H "Content-Type: application/json" -d '{"item":"pre-rollout-sanity-check"}')
echo "      $V1_RESULT"
kill "$PF_PID" >/dev/null 2>&1 || true
wait "$PF_PID" 2>/dev/null || true
echo "$V1_RESULT" | grep -q '"status": "ok"' || { echo "v1 sanity check failed - environment isn't healthy, aborting"; exit 1; }

echo "[7/8] Rolling out checkout-api revision 2 (the actual incident)..."
kubectl --context "${CTX}" apply -f manifests/checkout-api-v2.yaml
kubectl --context "${CTX}" rollout status deployment/checkout-api -n "${NS}" --timeout=180s

echo "[8/8] Confirming the page's claim: rollout succeeded, pods Ready..."
kubectl --context "${CTX}" get pods -n "${NS}" -l app=checkout-api -o wide

echo
echo "Done. The incident is already live."
echo "  Context: ${CTX}"
echo
echo "Try:"
echo "  kubectl --context ${CTX} rollout status deployment/checkout-api"
echo "  kubectl --context ${CTX} get pods -l app=checkout-api"
echo "  kubectl --context ${CTX} port-forward svc/checkout-api 18080:80 &"
echo '  curl -s -X POST http://localhost:18080/checkout -H "Content-Type: application/json" -d "{\"item\":\"widget\"}"'
