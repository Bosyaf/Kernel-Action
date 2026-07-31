#!/usr/bin/env bash
[ -z "$KERNEL_SRC" ] && KERNEL_SRC="../../common"

MODULE_VERSION_FILE="${KERNEL_SRC}/kernel/module/version.c"
PATCHER="./patch.py"

if [ -f "$MODULE_VERSION_FILE" ]; then
    echo "📦 Modül sürüm kontrolü devre dışı bırakılıyor..."
    python3 "$PATCHER" "$MODULE_VERSION_FILE" || { echo "❌ Bypass failed!"; exit 1; }
    echo "✅ Module version bypass applied!"
else
    echo "⚠️ version.c bulunamadı, atlanıyor."
fi