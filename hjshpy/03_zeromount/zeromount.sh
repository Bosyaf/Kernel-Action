#!/usr/bin/env bash

# ======================================================
# 📦 STANDALONE ADDON — ZeroMount (VFS path redirection engine)
# ======================================================

# --- STANDALONE (TEK BAŞINA) ÇALIŞTIRMA KALKANI ---
KERNEL_SRC="${KERNEL_SRC:-$(pwd)}"
# Python dosyalarının bu script ile aynı klasörde olduğunu otomatik bulur:
PATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

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

quit_script() {
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then exit 0; else return 0; fi
}
# ----------------------------------------------------

ZEROMOUNT_PATCH_URL="https://raw.githubusercontent.com/Enginex0/Super-Builders/main/android14-6.1/ReSukiSU/patches/60_zeromount-android14-6.1.patch"
ZEROMOUNT_PATCH="/tmp/60_zeromount-android14-6.1.patch"

log "Downloading ZeroMount kernel patch..."
retry 3 run_quiet curl -fSL "$ZEROMOUNT_PATCH_URL" -o "$ZEROMOUNT_PATCH" \
    || { warn "ZeroMount patch download failed — skipping"; quit_script; }

log "Stripping readdir.c hunk from patch..."
python3 "${PATCHER_DIR}/strip_readdir_hunk.py" "$ZEROMOUNT_PATCH" \
    || { warn "ZeroMount: strip_readdir_hunk failed — skipping"; rm -f "$ZEROMOUNT_PATCH"; quit_script; }

log "Stripping namei.c hunks from patch..."
python3 "${PATCHER_DIR}/strip_namei_hunk.py" "$ZEROMOUNT_PATCH" \
    || { warn "ZeroMount: strip_namei_hunk failed — skipping"; rm -f "$ZEROMOUNT_PATCH"; quit_script; }

log "Applying ZeroMount kernel patch..."
if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$ZEROMOUNT_PATCH" > /dev/null 2>&1; then
    log "ZeroMount patch already applied, skipping."
else
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$ZEROMOUNT_PATCH" > /tmp/zm_patch.log 2>&1 \
        || error "ZeroMount patch failed — check /tmp/zm_patch.log for details"
    log "ZeroMount patch applied ✅"
    rm -f /tmp/zm_patch.log
fi

rm -f "$ZEROMOUNT_PATCH"

log "Injecting ZeroMount hooks into namei.c (include, getname hook, permission checks)..."
python3 "${PATCHER_DIR}/inject_namei.py" "${KERNEL_SRC}/fs/namei.c" \
    || error "ZeroMount: namei.c injection failed!"
log "namei.c injected ✅"

log "Fixing task_mmu.c scope issue (zeromount call outside inode scope)..."
python3 "${PATCHER_DIR}/fix_taskmmu.py" "${KERNEL_SRC}/fs/proc/task_mmu.c" \
    || error "ZeroMount: task_mmu.c fix failed!"
log "task_mmu.c fixed ✅"

log "Injecting ZeroMount hooks into readdir.c (directory listing support)..."
python3 "${PATCHER_DIR}/inject_readdir.py" "${KERNEL_SRC}/fs/readdir.c" \
    || error "ZeroMount: readdir.c injection failed!"
log "readdir.c injected ✅"

# Kernel Konfigürasyonunu Aktif Et (Orijinal dosyada eksikti, eklendi)
log "Enabling ZeroMount config..."
GKI_DEFCONFIG="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if [ -f "$GKI_DEFCONFIG" ]; then
    if ! grep -q "^CONFIG_ZEROMOUNT=y" "$GKI_DEFCONFIG"; then
        echo "CONFIG_ZEROMOUNT=y" >> "$GKI_DEFCONFIG"
        log "CONFIG_ZEROMOUNT=y defconfig'e eklendi ✅"
    fi
fi

log "ZeroMount integrated ✅"
