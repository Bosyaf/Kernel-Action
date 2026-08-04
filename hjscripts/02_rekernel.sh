#!/usr/bin/env bash

# 1. Missing Functions Fix (Komut bulunamadı hatalarını bitirir)
log() { echo -e "\e[36m[LOG]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }

# 2. Kernel Yolu Ayarı (İki üst klasördeki common dizinine ulaşır)
[ -z "$KERNEL_SRC" ] && KERNEL_SRC="../../common"

# 3. Patcher Yolu Ayarı (Script ile aynı klasördeki inject.py)
REKERNEL_PATCHER="./inject.py"
REKERNEL_HEADER="${KERNEL_SRC}/drivers/android/rekernel.h"

log "📦 Integrating Re:Kernel..."

# 4. Python Enjeksiyonunu Başlat
if [ -f "$REKERNEL_PATCHER" ]; then
    python3 "$REKERNEL_PATCHER" "$KERNEL_SRC" \
        || error "Re:Kernel: injection failed!"
else
    error "Re:Kernel: inject.py bulunamadı!"
fi

# 5. Dosya Oluştu mu Kontrol Et
[ -f "$REKERNEL_HEADER" ] \
    || error "Re:Kernel: rekernel.h oluşturulamadı!"

# 6. Kancaları Doğrula (Marker Kontrolü)
log "🔍 Verifying Re:Kernel hook markers in source files..."
MARKER="Re:Kernel"
for _file in \
    "${KERNEL_SRC}/drivers/android/binder.c" \
    "${KERNEL_SRC}/drivers/android/binder_alloc.c" \
    "${KERNEL_SRC}/kernel/signal.c"; do
    if [ -f "$_file" ]; then
        grep -q "$MARKER" "$_file" \
            || error "Re:Kernel: hook marker missing in ${_file##*/} — injection silently failed!"
    else
        warn "Re:Kernel: $_file bulunamadı, doğrulama atlanıyor."
    fi
done

log "✅ Re:Kernel integrated and verified!"
exit 0
