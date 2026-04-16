#!/usr/bin/env bash
set -eu

GKI_ROOT=$(pwd)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# =========================================
# 🔍 INITIALIZE VARIABLES
# =========================================
if test -d "$GKI_ROOT/common/drivers"; then
    DRIVER_DIR="$GKI_ROOT/common/drivers"
elif test -d "$GKI_ROOT/drivers"; then
    DRIVER_DIR="$GKI_ROOT/drivers"
else
    echo '[ERROR] "drivers/" directory not found.'
    exit 127
fi

DRIVER_MAKEFILE="$DRIVER_DIR/Makefile"
DRIVER_KCONFIG="$DRIVER_DIR/Kconfig"
KSU_DIR="$GKI_ROOT/KernelSU/kernel"

# =========================================
# 🧹 CLEANUP (optional, --cleanup flag)
# =========================================
perform_cleanup() {
    echo "[+] Cleaning up..."
    [ -L "$DRIVER_DIR/kernelsu" ] && rm "$DRIVER_DIR/kernelsu" && echo "[-] Symlink removed."
    grep -q "kernelsu" "$DRIVER_MAKEFILE" && sed -i '/kernelsu/d' "$DRIVER_MAKEFILE" && echo "[-] Makefile reverted."
    grep -q "drivers/kernelsu/Kconfig" "$DRIVER_KCONFIG" && sed -i '/drivers\/kernelsu\/Kconfig/d' "$DRIVER_KCONFIG" && echo "[-] Kconfig reverted."
    if [ -d "$GKI_ROOT/KernelSU" ]; then
        rm -rf "$GKI_ROOT/KernelSU" && echo "[-] KernelSU directory deleted."
    fi
}

if [ "${1:-}" = "--cleanup" ]; then
    perform_cleanup
    exit 0
fi

# =========================================
# 📥 CLONE RESUKISU
# =========================================
echo "[+] Setting up ReSukiSU..."

if [ ! -d "$GKI_ROOT/KernelSU" ]; then
    git clone https://github.com/chainosama/ReSukiSU KernelSU
    echo "[+] Repository cloned."
fi

cd "$GKI_ROOT/KernelSU"
git stash && echo "[-] Stashed current changes."
if [ "$(git status | grep -Po 'v\d+(\.\d+)*' | head -n1)" ]; then
    git checkout main && echo "[-] Switched to main branch."
fi
git pull && echo "[+] Repository updated."
git checkout main && echo "[-] Checked out main branch."

cd "$DRIVER_DIR"
ln -sf "$(realpath --relative-to="$DRIVER_DIR" "$GKI_ROOT/KernelSU/kernel")" "kernelsu" && echo "[+] Symlink created."

grep -q "kernelsu" "$DRIVER_MAKEFILE" || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> "$DRIVER_MAKEFILE" && echo "[+] Modified Makefile."
grep -q "source \"drivers/kernelsu/Kconfig\"" "$DRIVER_KCONFIG" || sed -i "/endmenu/i\\source \"drivers/kernelsu/Kconfig\"" "$DRIVER_KCONFIG" && echo "[+] Modified Kconfig."

cd "$GKI_ROOT"

# =========================================
# 🔧 PATCH: uapi/supercall.h
# =========================================
SUPERCALL_H="$KSU_DIR/../uapi/supercall.h"

if grep -q "KSU_IOCTL_GET_HOOK_MODE" "$SUPERCALL_H"; then
    echo "[~] supercall.h already patched, skipping."
else
    sed -i 's|// Downstream add IOCTL command definitions|// KernelSU-Next Manager compatibility structs (nr 98, 99)\nstruct ksu_get_hook_mode_cmd {\n    char mode[16];\n};\n\nstruct ksu_get_version_tag_cmd {\n    char tag[32];\n};\n\nDEFINE_KSU_UAPI_CONST(__u32, KSU_IOCTL_GET_HOOK_MODE, _IOC(_IOC_READ, '"'"'K'"'"', 98, 0))\nDEFINE_KSU_UAPI_CONST(__u32, KSU_IOCTL_GET_VERSION_TAG, _IOC(_IOC_READ, '"'"'K'"'"', 99, 0))\n\n// Downstream add IOCTL command definitions|' "$SUPERCALL_H"
    echo "[+] supercall.h patched."
fi

# =========================================
# 🔧 PATCH: supercall/dispatch.c
# =========================================
DISPATCH_C="$KSU_DIR/supercall/dispatch.c"

if grep -q "do_get_hook_mode_compat" "$DISPATCH_C"; then
    echo "[~] dispatch.c already patched, skipping."
else
    python3 - "$DISPATCH_C" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    src = f.read()

# 1. Tambah include + KERNEL_NAME define
src = src.replace(
    '#include "supercall/supercall.h"',
    '#include "supercall/supercall.h"\n#include <linux/utsname.h>\n\n#ifndef KERNEL_NAME\n#define KERNEL_NAME "Veilkernel"\n#endif'
)

# 2. Modify version_full — append KERNEL_NAME
old_ver = '#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 13, 0)\n    strscpy(cmd.version_full, KSU_VERSION_FULL, sizeof(cmd.version_full));\n#else\n    strlcpy(cmd.version_full, KSU_VERSION_FULL, sizeof(cmd.version_full));\n#endif'
new_ver = (
    'char ksu_ver[32] = {0};\n'
    '    const char *dash = strchr(KSU_VERSION_FULL, \'-\');\n'
    '    if (dash)\n'
    '        strlcpy(ksu_ver, KSU_VERSION_FULL, (size_t)(dash - KSU_VERSION_FULL) + 1);\n'
    '    else\n'
    '        strlcpy(ksu_ver, KSU_VERSION_FULL, sizeof(ksu_ver));\n'
    '\n'
    '    snprintf(cmd.version_full, sizeof(cmd.version_full), "%s-" KERNEL_NAME, ksu_ver);'
)
src = src.replace(old_ver, new_ver)

# 3. Tambah fungsi compat setelah do_get_sulog_fd
hook_funcs = (
    '\n'
    '// KernelSU-Next Manager compat: GET_HOOK_MODE (cmd 98)\n'
    'static int do_get_hook_mode_compat(void __user *arg)\n'
    '{\n'
    '    struct ksu_get_hook_mode_cmd cmd = { 0 };\n'
    '#if defined(CONFIG_KSU_MANUAL_HOOK)\n'
    '    strncpy(cmd.mode, "Manual", sizeof(cmd.mode) - 1);\n'
    '#elif defined(CONFIG_KSU_SUSFS)\n'
    '    strncpy(cmd.mode, "Inline (SusFS)", sizeof(cmd.mode) - 1);\n'
    '#elif defined(KSU_TP_HOOK)\n'
    '    strncpy(cmd.mode, "Kprobes", sizeof(cmd.mode) - 1);\n'
    '#else\n'
    '    strncpy(cmd.mode, "Inline", sizeof(cmd.mode) - 1);\n'
    '#endif\n'
    '    if (copy_to_user(arg, &cmd, sizeof(cmd))) {\n'
    '        pr_err("get_hook_mode_compat: copy_to_user failed\\n");\n'
    '        return -EFAULT;\n'
    '    }\n'
    '    return 0;\n'
    '}\n'
    '\n'
    '// KernelSU-Next Manager compat: GET_VERSION_TAG (cmd 99)\n'
    'static int do_get_version_tag_compat(void __user *arg)\n'
    '{\n'
    '    struct ksu_get_version_tag_cmd cmd = { 0 };\n'
    '    char ksu_ver[32] = {0};\n'
    '    const char *sep = strchr(KSU_VERSION_FULL, \'-\');\n'
    '    if (sep)\n'
    '        strlcpy(ksu_ver, KSU_VERSION_FULL, (size_t)(sep - KSU_VERSION_FULL) + 1);\n'
    '    else\n'
    '        strlcpy(ksu_ver, KSU_VERSION_FULL, sizeof(ksu_ver));\n'
    '    snprintf(cmd.tag, sizeof(cmd.tag), "%s-" KERNEL_NAME, ksu_ver);\n'
    '    if (copy_to_user(arg, &cmd, sizeof(cmd))) {\n'
    '        pr_err("get_version_tag_compat: copy_to_user failed\\n");\n'
    '        return -EFAULT;\n'
    '    }\n'
    '    return 0;\n'
    '}\n'
)

src = re.sub(
    r'(static int do_get_sulog_fd.*?return ksu_install_sulog_fd\(\);\n\})',
    lambda m: m.group(1) + hook_funcs,
    src, flags=re.DOTALL
)

# 4. Tambah handler di tabel setelah GET_SULOG_FD
old_entry = (
    '    {\n'
    '        .cmd = KSU_IOCTL_GET_SULOG_FD,\n'
    '        .name = "GET_SULOG_FD",\n'
    '        .handler = do_get_sulog_fd,\n'
    '        .perm_check = only_root\n'
    '    },'
)
new_entry = (
    '    {\n'
    '        .cmd = KSU_IOCTL_GET_SULOG_FD,\n'
    '        .name = "GET_SULOG_FD",\n'
    '        .handler = do_get_sulog_fd,\n'
    '        .perm_check = only_root\n'
    '    },\n'
    '    {\n'
    '        .cmd = KSU_IOCTL_GET_HOOK_MODE,\n'
    '        .name = "GET_HOOK_MODE",\n'
    '        .handler = do_get_hook_mode_compat,\n'
    '        .perm_check = always_allow\n'
    '    },\n'
    '    {\n'
    '        .cmd = KSU_IOCTL_GET_VERSION_TAG,\n'
    '        .name = "GET_VERSION_TAG",\n'
    '        .handler = do_get_version_tag_compat,\n'
    '        .perm_check = always_allow\n'
    '    },'
)
src = src.replace(old_entry, new_entry)

with open(path, 'w') as f:
    f.write(src)
print("[+] dispatch.c patched.")
PYEOF
fi

# =========================================
# 🔧 PATCH: manager_sign.h (delta — append missing managers)
# =========================================
MANAGER_SIGN_H="$KSU_DIR/manager/manager_sign.h"

if grep -q "EXPECTED_SIZE_VORTEXSU" "$MANAGER_SIGN_H" 2>/dev/null; then
    echo "[~] manager_sign.h already patched, skipping."
else
    sed -i 's|#endif /\* MANAGER_SIGN_H \*/|// WildKernels/Wild_KSU\n#define EXPECTED_SIZE_WILDKSU 0x381\n#define EXPECTED_HASH_WILDKSU "52d52d8c8bfbe53dc2b6ff1c613184e2c03013e090fe8905d8e3d5dc2658c2e4"\n\n// KernelSU-Next/KernelSU-Next\n#define EXPECTED_SIZE_KSUNEXT 0x3e6\n#define EXPECTED_HASH_KSUNEXT "79e590113c4c4c0c222978e413a5faa801666957b1212a328e46c00c69821bf7"\n\n// MamboSU\n#define EXPECTED_SIZE_MAMBOSU 0x384\n#define EXPECTED_HASH_MAMBOSU "a9462b8b98ea1ca7901b0cbdcebfaa35f0aa95e51b01d66e6b6d2c81b97746d8"\n\n// VortexSU\n#define EXPECTED_SIZE_VORTEXSU 0x381\n#define EXPECTED_HASH_VORTEXSU "67eec44718428adad14e6a9dca57822759aba7e77a8cad7071f6f6704df8bb48"\n\n#endif \/* MANAGER_SIGN_H \*/|' "$MANAGER_SIGN_H"
    echo "[+] manager_sign.h patched."
fi

# =========================================
# 🔧 PATCH: apk_sign.c (delta — insert missing manager entries)
# =========================================
APK_SIGN_C="$KSU_DIR/manager/apk_sign.c"

if grep -q "EXPECTED_SIZE_VORTEXSU" "$APK_SIGN_C" 2>/dev/null; then
    echo "[~] apk_sign.c already patched, skipping."
else
    sed -i 's|#ifdef EXPECTED_SIZE|    { EXPECTED_SIZE_WILDKSU, EXPECTED_HASH_WILDKSU }, // WildKernels/Wild_KSU\n    { EXPECTED_SIZE_KSUNEXT, EXPECTED_HASH_KSUNEXT }, // KernelSU-Next/KernelSU-Next\n    { EXPECTED_SIZE_MAMBOSU, EXPECTED_HASH_MAMBOSU }, // MamboSU\n    { EXPECTED_SIZE_VORTEXSU, EXPECTED_HASH_VORTEXSU }, // VortexSU\n#ifdef EXPECTED_SIZE|' "$APK_SIGN_C"
    echo "[+] apk_sign.c patched."
fi

# =========================================
# 🔧 PATCH: Kbuild (version string + branding)
# =========================================
KBUILD="$KSU_DIR/Kbuild"

if grep -q "REPO_NAME := Veilkernel" "$KBUILD"; then
    echo "[~] Kbuild already patched, skipping."
else
    sed -i 's/REPO_NAME := ReSukiSU/REPO_NAME := Veilkernel/' "$KBUILD"
    sed -i 's|ifneq ($(KDIR),)|ifndef CONFIG_KSU_FULL_NAME_FORMAT|' "$KBUILD"
    sed -i '/CONFIG_KSU_FULL_NAME_FORMAT := /c\CONFIG_KSU_FULL_NAME_FORMAT := "%TAG_NAME%-%REPO_NAME%"' "$KBUILD"
    sed -i 's/^endif$/endif/' "$KBUILD"
    echo "[+] Kbuild patched."
fi

# =========================================
# ✅ DONE
# =========================================
echo ""
echo "[+] ReSukiSU setup + VeilKernel patches applied!"
echo "    - KernelSU cloned & symlinked"
echo "    - uapi/supercall.h"
echo "    - supercall/dispatch.c"
echo "    - manager_sign.h (+4 managers)"
echo "    - manager/apk_sign.c (+4 managers)"
echo "    - Kbuild"
