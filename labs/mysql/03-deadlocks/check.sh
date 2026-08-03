#!/usr/bin/env bash
# Lab 3 check — verifies BOTH transfers ended up applied (id=1 -> 950,
# id=2 -> 1050). If only one of the two transfers survived the deadlock
# and nobody retried the loser, the balances will not add up.
set -uo pipefail

fail() { echo "[FAIL] $1"; exit 1; }

if ! systemctl is-active --quiet mysql; then
    fail "mysql.service is not active"
fi

echo "[check] querying current balances..."
BAL1=$(mysql -uroot -prootpass appdb -N -e "SELECT balance FROM accounts WHERE id=1;" 2>/dev/null)
BAL2=$(mysql -uroot -prootpass appdb -N -e "SELECT balance FROM accounts WHERE id=2;" 2>/dev/null)

echo "[check] id=1 balance=$BAL1 (expected 950)"
echo "[check] id=2 balance=$BAL2 (expected 1050)"

[ -n "$BAL1" ] && [ -n "$BAL2" ] || fail "could not read balances - is the accounts table set up? (run setup.sh)"

[ "$BAL1" = "950" ] || fail "id=1 balance is $BAL1, expected 950 - one transfer never completed (the deadlock victim was never retried)"
[ "$BAL2" = "1050" ] || fail "id=2 balance is $BAL2, expected 1050 - one transfer never completed (the deadlock victim was never retried)"

TOTAL=$((BAL1 + BAL2))
[ "$TOTAL" -eq 2000 ] || fail "total balance is $TOTAL, expected 2000 - money was created or destroyed, something is very wrong"

echo "[PASS] both transfers applied: id=1=950, id=2=1050, total=2000"
exit 0
