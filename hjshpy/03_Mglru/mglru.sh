#!/usr/bin/env bash

# Script'in bulunduğu klasörü ve patch.py yolunu dinamik bul
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHER="${SCRIPT_DIR}/patch.py"

# KERNEL_SRC yolunu ayarla (boşsa dinamik tespit et)
if [ -z "$KERNEL_SRC" ]; then
    if [ -d "../../common" ]; then
        KERNEL_SRC="../../common"
    elif [ -d "common" ]; then
        KERNEL_SRC="common"
    else
        KERNEL_SRC="."
    fi
fi

VMSCAN_C="${KERNEL_SRC}/mm/vmscan.c"

echo "📦 MGLRU (Multi-Gen LRU) yaması kontrol ediliyor..."

# 1. Target vmscan.c dosyası var mı?
if [ ! -f "$VMSCAN_C" ]; then
    echo "⚠️ $VMSCAN_C bulunamadı, MGLRU yaması atlanıyor."
    exit 0
fi

# 2. patch.py dosyası var mı?
if [ ! -f "$PATCHER" ]; then
    echo "❌ $PATCHER bulunamadı!"
    exit 1
fi

# 3. vmscan.c içinde store_enabled() var mı?
if ! grep -q "^static ssize_t store_enabled(struct kobject \*kobj," "$VMSCAN_C"; then
    echo "⚠️ store_enabled() fonksiyonu $VMSCAN_C içinde bulunamadı — MGLRU bu kernelde yok veya yapısı farklı, atlanıyor."
    exit 0
fi

# 4. Python patcher çalıştır
python3 "$PATCHER" "$VMSCAN_C"
rc=$?

if [ $rc -eq 0 ]; then
    echo "✅ MGLRU force-enable (adaptive) başarıyla uygulandı! ✅"
else
    echo "❌ MGLRU: Patch scripti başarısız oldu!"
    exit 1
fi
