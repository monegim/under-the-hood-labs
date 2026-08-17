#!/usr/bin/env bash
# Lab 26 setup — Transparent Huge Pages (THP) set to "always" (a common
# default on older distros/kernels), which silently backs ANY eligible
# process's memory with 2MB huge pages, whether that process wants it or
# not. Compiles two tiny C programs: one simulating an ordinary
# memory-touching workload (never asks for huge pages), one that
# explicitly opts in via madvise(MADV_HUGEPAGE) — used later in the
# challenges. Saves the original THP setting so reset.sh can restore it.
set -euo pipefail

WORKDIR="/var/tmp/lab26"
mkdir -p "$WORKDIR"

THP_PATH="/sys/kernel/mm/transparent_hugepage/enabled"
if [ ! -f "$THP_PATH" ]; then
  echo "[setup] ERROR: $THP_PATH not found — this kernel may not support THP, or you're not on Linux." >&2
  exit 1
fi

echo "[setup] checking for gcc..."
if ! command -v gcc >/dev/null 2>&1; then
  echo "[setup] installing gcc via apt..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq gcc
fi

echo "[setup] saving the current THP setting (so reset.sh can restore it)..."
CURRENT=$(grep -oP '(?<=\[)[a-z]+(?=\])' "$THP_PATH")
echo "$CURRENT" > "$WORKDIR/original-thp-setting.txt"
echo "[setup] original setting was: $CURRENT"

cat > "$WORKDIR/touch_noopt.c" <<'EOF'
#include <sys/mman.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main() {
    size_t sz = 64 * 1024 * 1024;
    void *p = mmap(NULL, sz, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) { perror("mmap"); return 1; }
    memset(p, 1, sz);
    printf("touched %zu bytes at %p (no madvise call)\n", sz, p);
    sleep(1);
    return 0;
}
EOF

cat > "$WORKDIR/touch_madvise.c" <<'EOF'
#include <sys/mman.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main() {
    size_t sz = 64 * 1024 * 1024;
    void *p = mmap(NULL, sz, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) { perror("mmap"); return 1; }
    if (madvise(p, sz, MADV_HUGEPAGE) != 0) perror("madvise");
    memset(p, 1, sz);
    printf("touched %zu bytes at %p (explicit MADV_HUGEPAGE)\n", sz, p);
    sleep(1);
    return 0;
}
EOF

gcc "$WORKDIR/touch_noopt.c" -o "$WORKDIR/touch_noopt"
gcc "$WORKDIR/touch_madvise.c" -o "$WORKDIR/touch_madvise"

echo "[setup] INJECTING THE FAULT: setting THP to 'always'..."
echo always | sudo tee "$THP_PATH" >/dev/null
cat "$THP_PATH"

echo
echo "Done. Baseline thp_fault_alloc:"
grep thp_fault_alloc /proc/vmstat
echo "Run the ordinary (non-opted-in) workload and watch it move anyway:"
echo "  $WORKDIR/touch_noopt"
echo "  grep thp_fault_alloc /proc/vmstat"
