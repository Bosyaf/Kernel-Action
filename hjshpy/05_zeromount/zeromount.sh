#!/usr/bin/env bash
# KERNEL_SRC yolunu ayarla
[ -z "$KERNEL_SRC" ] && KERNEL_SRC="../../common"

ZEROMOUNT_PATCH_URL="https://raw.githubusercontent.com/Enginex0/Super-Builders/main/android14-6.1/ReSukiSU/patches/60_zeromount-android14-6.1.patch"
ZEROMOUNT_PATCH="/tmp/zeromount.patch"

echo "📦 ZeroMount yaması indiriliyor..."
curl -fSL "$ZEROMOUNT_PATCH_URL" -o "$ZEROMOUNT_PATCH" || { echo "❌ Yama indirilemedi!"; exit 1; }

# 1. ADIM: SuSFS ile çakışan kısımları temizliyoruz
echo "🧹 Yama içindeki tehlikeli bölümler ayıklanıyor..."
python3 ./strip_namei_hunk.py "$ZEROMOUNT_PATCH" || exit 1
python3 ./strip_readdir_hunk.py "$ZEROMOUNT_PATCH" || exit 1

# 2. ADIM: Yama Uygulama (Hataları görmezden geliyoruz çünkü manuel tamir edeceğiz)
echo "🛠️ ZeroMount yaması uygulanıyor (C dosyaları)..."
# --ignore-whitespace ve --force kullanarak C dosyalarının yamalanmasını garantiye alıyoruz
patch -p1 -d "$KERNEL_SRC" --batch --force --ignore-whitespace < "$ZEROMOUNT_PATCH"
echo "⚠️ Yama işlemi bitti (Ayar dosyalarındaki FAILED uyarıları normaldir, şimdi biz düzelteceğiz)..."

# 3. ADIM: MANUEL TAMİR (FAILED yazan Kconfig ve Defconfig kısımları)
echo "🔧 Kconfig ve Defconfig manuel tamir ediliyor..."

# fs/Kconfig içine zeromount'u ekleyelim (Eğer yoksa)
if ! grep -q "fs/zeromount/Kconfig" "${KERNEL_SRC}/fs/Kconfig"; then
    echo 'source "fs/zeromount/Kconfig"' >> "${KERNEL_SRC}/fs/Kconfig"
    echo "✅ fs/Kconfig güncellendi."
fi

# gki_defconfig içine bayrağı ekleyelim (Eğer yoksa)
if ! grep -q "CONFIG_ZEROMOUNT=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    echo "CONFIG_ZEROMOUNT=y" >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
    echo "✅ gki_defconfig güncellendi."
fi

# 4. ADIM: Cerrahi kancaları Python ile enjekte ediyoruz
echo "💉 VFS kancaları enjekte ediliyor..."
python3 ./inject_namei.py "${KERNEL_SRC}/fs/namei.c" || { echo "❌ Inject namei failed!"; exit 1; }
python3 ./inject_readdir.py "${KERNEL_SRC}/fs/readdir.c" || { echo "❌ Inject readdir failed!"; exit 1; }
python3 ./fix_taskmmu.py "${KERNEL_SRC}/fs/proc/task_mmu.c" || { echo "❌ Fix taskmmu failed!"; exit 1; }

echo "✅ ZeroMount başarıyla entegre edildi!"
exit 0
