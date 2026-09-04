#!/bin/bash

# Çalışma dizinini argümandan al (Workflow'dan $GITHUB_WORKSPACE geliyor)
WORKSPACE_DIR="${1:-$PWD}"
# Kernel kaynaklarının olduğu klasör (Workflow'da 'common' klasörüne çekiliyor)
COMMON_DIR="$WORKSPACE_DIR/common"

echo "================================================================="
echo "🚀 [MODULELIST.SH] ZRAM / ZSMALLOC Temizlik Scripti Başlatıldı!"
echo "📂 Hedef Kaynak Dizini: $COMMON_DIR"
echo "================================================================="

# common dizini var mı kontrol et
if [ ! -d "$COMMON_DIR" ]; then
    echo "❌ HATA: '$COMMON_DIR' dizini bulunamadı. Lütfen yolu kontrol edin!"
    exit 1
fi

# ===================================================================
# GÖREV YAPAN ANA FONKSİYON
# ===================================================================
clean_module() {
    local target_name="$1"
    local search_pattern="$2"

    echo ""
    echo "🔍 Tarama Başladı:"
    echo "   Aranan Hedef : '$target_name'"
    echo "   Dosya Tipi   : '$search_pattern'"
    echo "-----------------------------------------------------------------"

    # find ile belirtilen desendeki dosyaları bul
    local files_found
    files_found=$(find "$COMMON_DIR" -type f -name "$search_pattern" 2>/dev/null)

    if [ -z "$files_found" ]; then
        echo "   ℹ️ '$search_pattern' formatında dosya bulunamadı, atlanıyor."
        return
    fi

    local change_count=0

    # Bulunan her dosya için işlem yap
    for file in $files_found; do
        # Dosyanın içinde aradığımız kelime var mı?
        if grep -q "$target_name" "$file"; then
            echo "   📄 Eşleşme Bulundu: $file"
            echo "      [SİLİNMEDEN ÖNCEKİ SATIRLAR]:"
            
            # Silinmeden önce neyi sileceğimizi satır numarasıyla loga yazdır
            grep -n "$target_name" "$file" | while read -r line; do
                echo "      ❌ $line"
            done

            # SİLME İŞLEMİ: sed ile içinde hedef geçen tüm satırları sil
            sed -i "/$target_name/d" "$file"

            # Kontrol Et: Gerçekten silinmiş mi?
            if grep -q "$target_name" "$file"; then
                echo "      ⚠️ UYARI: Silme işlemi başarısız oldu! (Dosya salt okunur olabilir)"
            else
                echo "      ✅ BAŞARILI: İlgili satırlar dosyadan tamamen temizlendi."
                change_count=$((change_count + 1))
            fi
            echo "      -------------------------------------------------"
        fi
    done

    # Eğer hiçbir dosyada değişiklik yapılmadıysa bilgi ver
    if [ "$change_count" -eq 0 ]; then
        echo "   ✅ İncelenen dosyalarda '$target_name' kaydı bulunamadı (Zaten temiz)."
    fi
}

# ===================================================================
# TEMİZLENECEK HEDEFLER
# ===================================================================

# 1. Standart GKI Module Load listelerini temizle (modules.load vb.)
clean_module "zram.ko" "*modules.load*"
clean_module "zsmalloc.ko" "*modules.load*"

# 2. Bazel derleme listelerinden (GKI v2 için) temizle
clean_module "zram.ko" "*.bzl"
clean_module "zsmalloc.ko" "*.bzl"

# 3. Blocklist ve ek DLKM (Vendor/System) listelerinden temizle
clean_module "zram.ko" "*blocklist"
clean_module "zsmalloc.ko" "*blocklist"

echo ""
echo "================================================================="
echo "🎉 [MODULELIST.SH] Kernel Modül Listesi Temizliği Tamamlandı!"
echo "================================================================="
