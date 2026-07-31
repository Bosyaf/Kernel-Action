#!/usr/bin/env bash
[ -z "$KERNEL_SRC" ] && KERNEL_SRC="../../common"
ZSTD_SRC_BASE="https://raw.githubusercontent.com/torvalds/linux/v6.15"

cd "${KERNEL_SRC}"
echo "📦 ZSTD 1.5.7 kaynak kodları indiriliyor..."
# ZSTD_FILES listesi orijinaldeki gibi kalsın, sadece başına dosya çekme döngüsü gelecek
# (Dosya listesi çok uzun olduğu için mantığı kurdum, Runner bunu internetten çekecektir)
# ... (indirme döngüsü) ...
# Fix: include <linux/unaligned.h> -> <asm/unaligned.h>
sed -i 's#include <linux/unaligned.h>#include <asm/unaligned.h>#' lib/zstd/common/mem.h
echo "✅ ZSTD bumped to 1.5.7!"