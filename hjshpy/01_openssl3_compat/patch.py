import sys

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    path = sys.argv[1]

    with open(path, "r") as f:
        content = f.read()

    # 1. Kontrol: Eğer dosya zaten senin attığın gibi en temiz halindeyse
    # Yani key_pass tanımlı ve başında ifdef engeli yoksa:
    if "static const char *key_pass;" in content and "#ifdef USE_PKCS11_ENGINE" not in content:
        print("[info] openssl3_compat: Dosya zaten uyumlu (Static tanım açık), işlem gerekmiyor ✅")
        sys.exit(0)

    # 2. Kontrol: Eğer dosya zaten daha önce yamalanmışsa:
    if "#define USE_PKCS11_ENGINE" in content:
        print("[info] openssl3_compat: Zaten yamalanmış — geçiliyor ✅")
        sys.exit(0)

    # 3. Kontrol: Eğer dosya "hatalı" versiyon ise (ifdef var ama define yoksa):
    ANCHOR = "#ifdef USE_PKCS11_ENGINE\nstatic const char *key_pass;\n#endif"
    DEFINE_BLOCK = (
        "#if !defined(OPENSSL_NO_ENGINE) && !defined(OPENSSL_NO_DEPRECATED_3_0)\n"
        "#define USE_PKCS11_ENGINE\n"
        "#endif\n"
    )

    if ANCHOR in content:
        content = content.replace(ANCHOR, DEFINE_BLOCK + ANCHOR, 1)
        with open(path, "w") as f:
            f.write(content)
        print("[info] extract-cert.c başarıyla yamalandı ✅")
    else:
        # Eğer yukarıdakilerin hiçbiri değilse ama key_pass oradaysa, 
        # Runner'ı durdurma çünkü dosya zaten iş görür durumda.
        if "static const char *key_pass;" in content:
            print("[info] openssl3_compat: Farklı yapı ama key_pass mevcut, güvenli geçiş ✅")
            sys.exit(0)
        else:
            print(f"[error] openssl3_compat: Kritik hata, dosyada key_pass bulunamadı!", file=sys.stderr)
            sys.exit(1)

if __name__ == "__main__":
    main()
