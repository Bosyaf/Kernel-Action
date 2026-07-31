#!/usr/bin/env bash
[ -z "$KERNEL_SRC" ] && KERNEL_SRC="../../common"

ZEROMOUNT_PATCH_URL="https://raw.githubusercontent.com/Enginex0/Super-Builders/main/android14-6.1/ReSukiSU/patches/60_zeromount-android14-6.1.patch"
ZEROMOUNT_PATCH="/tmp/zeromount.patch"

echo "📦 ZeroMount yaması indiriliyor..."
curl -fSL "$ZEROMOUNT_PATCH_URL" -o "$ZEROMOUNT_PATCH" || { echo "❌ Yama indirilemedi!"; exit 1; }

# 1. ADIM: Temizlik
echo "🧹 Yama içindeki tehlikeli bölümler ayıklanıyor..."
python3 ./strip_namei_hunk.py "$ZEROMOUNT_PATCH" || exit 1
python3 ./strip_readdir_hunk.py "$ZEROMOUNT_PATCH" || exit 1

# 2. ADIM: Yama Uygulama (Hataları görmezden geliyoruz çünkü manuel tamir edeceğiz)
echo "🛠️ ZeroMount yaması uygulanıyor (C dosyaları)..."
patch -p1 -d "$KERNEL_SRC" --batch --force < "$ZEROMOUNT_PATCH" || echo "⚠️ Bazı ayar dosyaları manuel tamir edilecek..."

# 3. ADIM: MANUEL TAMİR (FAILED yazan yerleri sed ile düzeltiyoruz)
echo "🔧 Kconfig ve Defconfig manuel tamir ediliyor..."
# fs/Kconfig içine menü girişini ekliyoruz
if ! grep -q "fs/zeromount/Kconfig" "${KERNEL_SRC}/fs/Kconfig"; then
    sed -i '/menu "File systems"/a source "fs/zeromount/Kconfig"' "${KERNEL_SRC}/fs/Kconfig"
fi

# gki_defconfig içine bayrağı ekliyoruz
if ! grep -q "CONFIG_ZEROMOUNT=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    echo "CONFIG_ZEROMOUNT=y" >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
fi

# 4. ADIM: Cerrahi kancaları Python ile enjekte ediyoruz (ASIL ÖNEMLİ KISIM)
echo "💉 VFS kancaları enjekte ediliyor..."
python3 ./inject_namei.py "${KERNEL_SRC}/fs/namei.c" || { echo "❌ Inject namei failed!"; exit 1; }
python3 ./inject_readdir.py "${KERNEL_SRC}/fs/readdir.c" || { echo "❌ Inject readdir failed!"; exit 1; }
python3 ./fix_taskmmu.py "${KERNEL_SRC}/fs/proc/task_mmu.c" || { echo "❌ Fix taskmmu failed!"; exit 1; }

echo "✅ ZeroMount manuel tamir ve enjeksiyonla başarıyla entegre edildi!"
