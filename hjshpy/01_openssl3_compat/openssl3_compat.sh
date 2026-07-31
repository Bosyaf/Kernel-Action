#!/usr/bin/env bash
# KERNEL_SRC yolunu ayarla
[ -z "$KERNEL_SRC" ] && KERNEL_SRC="../../common"

EXTRACT_CERT="${KERNEL_SRC}/certs/extract-cert.c"
PATCHER="./patch.py"

if [ -f "$EXTRACT_CERT" ]; then
    echo "📦 OpenSSL 3 compat yaması uygulanıyor..."
    python3 "$PATCHER" "$EXTRACT_CERT" || { echo "❌ OpenSSL 3 compat failed!"; exit 1; }
    echo "✅ OpenSSL 3 compat patched!"
else
    echo "⚠️ extract-cert.c bulunamadı, atlanıyor."
fi