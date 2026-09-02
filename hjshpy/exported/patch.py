import sys
import os
import glob
import shutil

def main():
    # Sistem genelde patch.py'ye argüman olarak hedef dizini (KERNEL_SRC) yollar.
    # Argüman gelmezse varsayılan olarak mevcut dizini (.) kullanırız.
    if len(sys.argv) > 1:
        kernel_src = sys.argv[1]
    else:
        kernel_src = "."

    # Silinecek dosyaların/klasörlerin yolu: android/abi_gki_protected_exports_*
    target_pattern = os.path.join(kernel_src, "android", "abi_gki_protected_exports_*")
    
    # Eşleşen tüm dosyaları ve klasörleri bul
    matching_paths = glob.glob(target_pattern)

    # Eğer silinecek bir şey yoksa başarılı sayıp geçiyoruz
    if not matching_paths:
        print("[info] protected_exports: Silinecek 'abi_gki_protected_exports' bulunamadı. Zaten temiz ✅")
        sys.exit(0)

    # Bulunan dosyaları sil (bash'teki rm -rf işleminin aynısı)
    for path in matching_paths:
        try:
            if os.path.isdir(path):
                shutil.rmtree(path) # Klasörse içindekilerle beraber sil
            else:
                os.remove(path)     # Dosyaysa direkt sil
            # print(f"[info] Silindi: {path}") # İstersen neyi sildiğini görmek için bu satırın başındaki '#' işaretini kaldırabilirsin
        except Exception as e:
            print(f"[error] protected_exports: {path} silinirken hata oluştu: {e}", file=sys.stderr)
            sys.exit(1)

    print("[info] protected_exports: Protected exports başarıyla temizlendi ✅")
    sys.exit(0)

if __name__ == "__main__":
    main()
  
