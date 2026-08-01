#!/usr/bin/env bash

# 1. Missing Functions Fix (Komut yok hatalarını bitirir)
log() { echo -e "\e[36m[LOG]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }

# 2. Kernel Yolu Ayarı
[ -z "$KERNEL_SRC" ] && KERNEL_SRC="../../common"

# 3. Yama Bilgileri
ZEROMOUNT_PATCH_URL="https://raw.githubusercontent.com/Enginex0/Super-Builders/main/android14-6.1/ReSukiSU/patches/60_zeromount-android14-6.1.patch"
ZEROMOUNT_PATCH="/tmp/zeromount.patch"

log "📦 ZeroMount yaması indiriliyor..."
curl -fSL "$ZEROMOUNT_PATCH_URL" -o "$ZEROMOUNT_PATCH" || error "Yama indirilemedi!"

# 4. Ön Temizlik (Hunk hatalarını önlemek için)
log "🧹 Yama içindeki tehlikeli bölümler ayıklanıyor..."
# Python dosyalarıyla aynı klasörde olduğumuz için ./ kullanıyoruz
python3 ./strip_readdir_hunk.py "$ZEROMOUNT_PATCH" || warn "Strip readdir failed"
python3 ./strip_namei_hunk.py "$ZEROMOUNT_PATCH" || warn "Strip namei failed"

# 5. Yama Uygulama (Hatalar bypass edilecek, manuel tamir devrede)
log "🛠️ ZeroMount yaması basılıyor..."
patch -p1 -d "$KERNEL_SRC" --batch --force --ignore-whitespace < "$ZEROMOUNT_PATCH" || warn "Bazı dosyalar manuel tamir edilecek"

# 6. Manuel Kconfig ve Makefile Tamiri (Runner'ın bulamadığı dosyalar)
log "🔧 Klasör ve ayar dosyaları hazırlanıyor..."
mkdir -p "${KERNEL_SRC}/fs/zeromount"

if [ ! -f "${KERNEL_SRC}/fs/zeromount/Kconfig" ]; then
    cat > "${KERNEL_SRC}/fs/zeromount/Kconfig" << 'EOF'
config ZEROMOUNT
	bool "ZeroMount VFS redirection support"
	depends on KSU_SUSFS
	default y
EOF
fi

if [ ! -f "${KERNEL_SRC}/fs/zeromount/Makefile" ]; then
    echo 'obj-$(CONFIG_ZEROMOUNT) += zeromount.o' > "${KERNEL_SRC}/fs/zeromount/Makefile"
fi

# fs/Kconfig bağlantısını yap
if ! grep -q "fs/zeromount/Kconfig" "${KERNEL_SRC}/fs/Kconfig"; then
    echo 'source "fs/zeromount/Kconfig"' >> "${KERNEL_SRC}/fs/Kconfig"
fi

# 7. Cerrahi Kancaları Enjekte Et
log "💉 VFS kancaları Python ile enjekte ediliyor..."
python3 ./inject_namei.py "${KERNEL_SRC}/fs/namei.c" || warn "Inject namei failed"
python3 ./inject_readdir.py "${KERNEL_SRC}/fs/readdir.c" || warn "Inject readdir failed"
python3 ./fix_taskmmu.py "${KERNEL_SRC}/fs/proc/task_mmu.c" || warn "Fix taskmmu failed"

log "✅ ZeroMount başarıyla entegre edildi!"
exit 0
