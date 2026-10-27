#!/usr/bin/env bash
[ -z "$KERNEL_SRC" ] && KERNEL_SRC="../../common"

MKCOMPILE_H="${KERNEL_SRC}/scripts/mkcompile_h"
PATCHER="./patch.py"
# Buraya Runner'da görünmesini istediğin ismi yaz
COMPILER_STRING="ZyC Clang 22.0.0"

if [ -f "$MKCOMPILE_H" ]; then
    echo "📦 Compiler string güncelleniyor: $COMPILER_STRING"
    python3 "$PATCHER" "$MKCOMPILE_H" "$COMPILER_STRING" || { echo "❌ String failed!"; exit 1; }
    echo "✅ Compiler string patched!"
fi
