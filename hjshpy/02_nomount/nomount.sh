#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — NoMount (VFS path injection framework)
# ======================================================
# Repo: https://github.com/maxsteeel/nomount
# Status: Beta

# --- STANDALONE (TEK BAŞINA) ÇALIŞTIRMA KALKANI ---
# Eğer ana sistemden (framework) gelmiyorsa eksikleri otomatik tamamlar
KERNEL_SRC="${KERNEL_SRC:-$(pwd)}"
KERNEL_VERSION="${KERNEL_VERSION:-6.1}"

if ! type log >/dev/null 2>&1; then
    log() { echo -e "[\033[1;32mINFO\033[0m] $*"; }
    warn() { echo -e "[\033[1;33mWARN\033[0m] $*"; }
    error() { echo -e "[\033[1;31mERROR\033[0m] $*"; exit 1; }
    run_quiet() { "$@" >/dev/null 2>&1; }
    retry() {
        local tries=$1; shift
        for ((i=1; i<=tries; i++)); do
            "$@" && return 0
        done
        return 1
    }
fi
# Tek başına çalıştırıldığında 'return' komutu hata vermesin diye yönlendirici:
quit_script() {
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then exit 0; else return 0; fi
}
# ----------------------------------------------------

NOMOUNT_REPO="https://github.com/maxsteeel/nomount"
NOMOUNT_DIR="/tmp/nomount_src"
NOMOUNT_PATCH_NAME="nomount_${KERNEL_VERSION}_kernel_integration.patch"

log "Integrating NoMount..."

[ -d "$NOMOUNT_DIR" ] && rm -rf "$NOMOUNT_DIR"
git config --global http.connectTimeout 30
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 30
retry 3 run_quiet git clone -q --depth=1 "$NOMOUNT_REPO" "$NOMOUNT_DIR" \
    || { warn "NoMount clone failed — skipping"; quit_script; }

NOMOUNT_PATCH="${NOMOUNT_DIR}/kernel/patches/${NOMOUNT_PATCH_NAME}"
if [ ! -f "$NOMOUNT_PATCH" ]; then
    warn "NoMount patch not found for kernel ${KERNEL_VERSION} — skipping"
    rm -rf "$NOMOUNT_DIR"
    quit_script
fi

log "Copying NoMount source files..."
cp "${NOMOUNT_DIR}/kernel/src/nomount.c" "${KERNEL_SRC}/fs/nomount.c"
cp "${NOMOUNT_DIR}/kernel/src/nomount.h" "${KERNEL_SRC}/fs/nomount.h"
log "NoMount source files copied ✅"

log "Applying NoMount kernel patch..."
if patch -p1 --fuzz=10 --dry-run --reverse -d "$KERNEL_SRC" < "$NOMOUNT_PATCH" > /dev/null 2>&1; then
    log "NoMount patch already applied, skipping."
else
    patch -p1 --fuzz=10 --forward -d "$KERNEL_SRC" < "$NOMOUNT_PATCH" \
        && log "NoMount patch applied ✅" \
        || warn "NoMount patch: some hunks failed — continuing"
    find "$KERNEL_SRC" -name "*.rej" -delete 2>/dev/null || true
fi

# Guard: verify NoMount was actually wired in before enabling the config.
if ! grep -rlF '#include "nomount.h"' "${KERNEL_SRC}/fs/" 2>/dev/null \
        | grep -qv '/nomount\.c$'; then
    warn "NoMount: no caller includes nomount.h after patch — integration may have failed entirely"
    warn "NoMount integration incomplete — kernel will build without NoMount"
    rm -rf "$NOMOUNT_DIR"
    quit_script
fi

rm -rf "$NOMOUNT_DIR"

log "Enabling NoMount config..."
if ! grep -q "^CONFIG_NOMOUNT=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_NOMOUNT=y
CONFIGS
fi

log "NoMount integrated ✅"

