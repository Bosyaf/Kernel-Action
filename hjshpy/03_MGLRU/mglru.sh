#!/usr/bin/env bash
VMSCAN_C="${KERNEL_SRC}/mm/vmscan.c"
PATCHER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patch.py"
[ -f "$VMSCAN_C" ] || { warn "mm/vmscan.c not found, skipping mglru"; return 0; }
grep -q "^static ssize_t store_enabled(struct kobject \*kobj," "$VMSCAN_C" \
    || { warn "store_enabled() not found in this kernel's shape — MGLRU doesn't exist here or its shape changed, skipping"; return 0; }
python3 "$PATCHER" "$VMSCAN_C"
rc=$?
if [ $rc -eq 0 ]; then
    echo "[info] mglru force-enable (adaptive) applied ✅"
else
    echo "[error] mglru: patch script failed!"
fi
