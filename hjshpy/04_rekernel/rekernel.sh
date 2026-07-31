#!/usr/bin/env bash
[ -z "$KERNEL_SRC" ] && KERNEL_SRC="../../common"

REKERNEL_PATCHER="./inject.py"
REKERNEL_HEADER="${KERNEL_SRC}/drivers/android/rekernel.h"

echo "📦 Re:Kernel enjekte ediliyor..."
python3 "$REKERNEL_PATCHER" "$KERNEL_SRC" || { echo "❌ Re:Kernel failed!"; exit 1; }

if [ -f "$REKERNEL_HEADER" ]; then
    echo "✅ Re:Kernel integrated and verified!"
else
    echo "❌ rekernel.h oluşturulamadı!"; exit 1
fi