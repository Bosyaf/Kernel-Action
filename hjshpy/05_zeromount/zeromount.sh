#!/usr/bin/env bash
# KERNEL_SRC yolunu ayarla
[ -z "$KERNEL_SRC" ] && KERNEL_SRC="../../common"

# Orijinal yama linki
ZEROMOUNT_PATCH_URL="https://raw.githubusercontent.com/Enginex0/Super-Builders/main/android14-6.1/ReSukiSU/patches/60_zeromount-android14-6.1.patch"
ZEROMOUNT_PATCH="/tmp/zeromount.patch"

echo "📦 ZeroMount yaması indiriliyor..."
curl -fSL "$ZEROMOUNT_PATCH_URL" -o "$ZEROMOUNT_PATCH" || { echo "❌ Yama indirilemedi!"; exit 1; }

# 1. ADIM: Yama içindeki SuSFS ile çakışan kısımları temizliyoruz (Strip)
echo "🧹 Yama içindeki tehlikeli bölümler ayıklanıyor..."
python3 ./strip_namei_hunk.py "$ZEROMOUNT_PATCH" || { echo "❌ Strip namei failed!"; exit 1; }
python3 ./strip_readdir_hunk.py "$ZEROMOUNT_PATCH" || { echo "❌ Strip readdir failed!"; exit 1; }

# 2. ADIM: Temizlenmiş yamayı kernel ağacına basıyoruz
echo "🛠️ Temizlenmiş ZeroMount yaması uygulanıyor..."
patch -p1 -d "$KERNEL_SRC" < "$ZEROMOUNT_PATCH" || { echo "❌ Patch failed!"; exit 1; }

# 3. ADIM: Cerrahi kancaları Python ile dosyalara enjekte ediyoruz
echo "💉 VFS kancaları enjekte ediliyor..."
python3 ./inject_namei.py "${KERNEL_SRC}/fs/namei.c" || { echo "❌ Inject namei failed!"; exit 1; }
python3 ./inject_readdir.py "${KERNEL_SRC}/fs/readdir.c" || { echo "❌ Inject readdir failed!"; exit 1; }
python3 ./fix_taskmmu.py "${KERNEL_SRC}/fs/proc/task_mmu.c" || { echo "❌ Fix taskmmu failed!"; exit 1; }

# 4. ADIM: Config'i gki_defconfig'e ekle
if ! grep -q "CONFIG_ZEROMOUNT=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    echo "CONFIG_ZEROMOUNT=y" >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
fi

echo "✅ ZeroMount SuSFS ile tam uyumlu şekilde entegre edildi!"