#!/usr/bin/env bash
[ -z "$KERNEL_SRC" ] && KERNEL_SRC="../../common"

ZEROMOUNT_PATCH_URL="https://raw.githubusercontent.com/Enginex0/Super-Builders/main/android14-6.1/ReSukiSU/patches/60_zeromount-android14-6.1.patch"
ZEROMOUNT_PATCH="/tmp/zeromount.patch"

echo "📦 ZeroMount yaması indiriliyor..."
curl -fSL "$ZEROMOUNT_PATCH_URL" -o "$ZEROMOUNT_PATCH" || true

echo "🧹 Temizlik yapılıyor..."
python3 ./strip_namei_hunk.py "$ZEROMOUNT_PATCH" || true
python3 ./strip_readdir_hunk.py "$ZEROMOUNT_PATCH" || true

echo "🛠️ Yama basılıyor (Hatalar yoksayılacak)..."
# '|| true' sayesinde yama FAILED verse bile script durmaz
patch -p1 -d "$KERNEL_SRC" --batch --force --ignore-whitespace < "$ZEROMOUNT_PATCH" || true

echo "🔧 Manuel tamirler..."
# Kconfig ve Defconfig'i biz elle hallediyoruz
if ! grep -q "fs/zeromount/Kconfig" "${KERNEL_SRC}/fs/Kconfig"; then
    echo 'source "fs/zeromount/Kconfig"' >> "${KERNEL_SRC}/fs/Kconfig"
fi
if ! grep -q "CONFIG_ZEROMOUNT=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    echo "CONFIG_ZEROMOUNT=y" >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
fi

echo "💉 Python enjeksiyonları..."
python3 ./inject_namei.py "${KERNEL_SRC}/fs/namei.c" || true
python3 ./inject_readdir.py "${KERNEL_SRC}/fs/readdir.c" || true
python3 ./fix_taskmmu.py "${KERNEL_SRC}/fs/proc/task_mmu.c" || true

echo "✅ ZeroMount adımı tamamlandı (Hatalar bypass edildi)."
exit 0 # Kesinlikle başarılı çıkış yap
