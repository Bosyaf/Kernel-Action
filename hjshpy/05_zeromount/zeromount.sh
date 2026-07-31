#!/usr/bin/env bash
[ -z "$KERNEL_SRC" ] && KERNEL_SRC="../../common"

ZEROMOUNT_PATCH_URL="https://raw.githubusercontent.com/Enginex0/Super-Builders/main/android14-6.1/ReSukiSU/patches/60_zeromount-android14-6.1.patch"
ZEROMOUNT_PATCH="/tmp/zeromount.patch"

echo "📦 ZeroMount yaması indiriliyor..."
curl -fSL "$ZEROMOUNT_PATCH_URL" -o "$ZEROMOUNT_PATCH" || true

# KLASÖRÜ MANUEL OLUŞTURUYORUZ (Hatanın kökten çözümü)
mkdir -p "${KERNEL_SRC}/fs/zeromount"

echo "🧹 Temizlik yapılıyor..."
python3 ./strip_namei_hunk.py "$ZEROMOUNT_PATCH" || true
python3 ./strip_readdir_hunk.py "$ZEROMOUNT_PATCH" || true

echo "🛠️ Yama basılıyor..."
patch -p1 -d "$KERNEL_SRC" --batch --force --ignore-whitespace < "$ZEROMOUNT_PATCH" || true

# EĞER PATCH DOSYAYI OLUŞTURAMADIYSA BİZ MANUEL OLUŞTURALIM (Sigorta)
if [ ! -f "${KERNEL_SRC}/fs/zeromount/Kconfig" ]; then
    echo "🔧 ZeroMount Kconfig manuel oluşturuluyor..."
    cat > "${KERNEL_SRC}/fs/zeromount/Kconfig" << 'EOF'
config ZEROMOUNT
	bool "ZeroMount VFS redirection support"
	depends on KSU_SUSFS
	default y
	help
	  Enable ZeroMount VFS path redirection engine.
EOF
fi

if [ ! -f "${KERNEL_SRC}/fs/zeromount/Makefile" ]; then
    echo "🔧 ZeroMount Makefile manuel oluşturuluyor..."
    echo 'obj-$(CONFIG_ZEROMOUNT) += zeromount.o' > "${KERNEL_SRC}/fs/zeromount/Makefile"
fi

echo "🔧 Ana Kconfig ve Defconfig ayarlanıyor..."
# Sadece dosya gerçekten varsa source ekle
if [ -f "${KERNEL_SRC}/fs/zeromount/Kconfig" ]; then
    if ! grep -q "fs/zeromount/Kconfig" "${KERNEL_SRC}/fs/Kconfig"; then
        echo 'source "fs/zeromount/Kconfig"' >> "${KERNEL_SRC}/fs/Kconfig"
    fi
fi

if ! grep -q "CONFIG_ZEROMOUNT=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    echo "CONFIG_ZEROMOUNT=y" >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
fi

echo "💉 Python enjeksiyonları..."
python3 ./inject_namei.py "${KERNEL_SRC}/fs/namei.c" || true
python3 ./inject_readdir.py "${KERNEL_SRC}/fs/readdir.c" || true
python3 ./fix_taskmmu.py "${KERNEL_SRC}/fs/proc/task_mmu.c" || true

echo "✅ ZeroMount başarıyla bağlandı."
exit 0
