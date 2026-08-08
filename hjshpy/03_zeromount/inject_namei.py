#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0

import sys

IDEMPOTENCY_MARKER = "#ifdef CONFIG_ZEROMOUNT"

INCLUDE_INJECT = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "#include <linux/zeromount.h>\n"
    "#endif\n"
)

GETNAME_INJECT = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "\tif (!IS_ERR(result)) {\n"
    "\t\tresult = zeromount_getname_hook(result);\n"
    "\t}\n"
    "#endif\n"
)

PERMISSION_INJECT = (
    "#ifdef CONFIG_ZEROMOUNT\n"
    "\tif (zeromount_is_injected_file(inode)) {\n"
    "\t\tif (mask & MAY_WRITE)\n"
    "\t\t\treturn -EACCES;\n"
    "\t\treturn 0;\n"
    "\t}\n"
    "\n"
    "\tif (S_ISDIR(inode->i_mode) && zeromount_is_traversal_allowed(inode, mask)) {\n"
    "\t\treturn 0;\n"
    "\t}\n"
    "#endif\n"
    "\n"
)

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path/to/fs/namei.c>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]

    with open(path, "r") as f:
        lines = f.readlines()

    # Zaten yamalanmış mı kontrolü
    if any(IDEMPOTENCY_MARKER in line for line in lines):
        print("[info] inject_namei: ZeroMount already injected — skipping ✅")
        sys.exit(0)

    # 1. Include Eklemesi
    for i, line in enumerate(lines):
        if '#include "mount.h"' in line:
            lines.insert(i + 1, INCLUDE_INJECT)
            break
    else:
        print("[error] inject_namei: include anchor not found!", file=sys.stderr)
        sys.exit(1)

    # 2. getname_flags Kancası
    in_getname = False
    for i, line in enumerate(lines):
        if "getname_flags(" in line:
            in_getname = True
        if in_getname and "audit_getname(result);" in line:
            lines.insert(i + 1, GETNAME_INJECT)
            break
    else:
        print("[error] inject_namei: getname_flags() anchor not found!", file=sys.stderr)
        sys.exit(1)

    # 3. generic_permission Kancası
    in_generic = False
    for i, line in enumerate(lines):
        if "generic_permission(" in line:
            in_generic = True
        if in_generic and "acl_permission_check(" in line:
            lines.insert(i, PERMISSION_INJECT)
            break
    else:
        print("[error] inject_namei: generic_permission() anchor not found!", file=sys.stderr)
        sys.exit(1)

    # 4. inode_permission Kancası
    in_inode = False
    for i, line in enumerate(lines):
        if "inode_permission(" in line:
            in_inode = True
        if in_inode and "sb_permission(" in line:
            lines.insert(i, PERMISSION_INJECT)
            break
    else:
        print("[error] inject_namei: inode_permission() anchor not found!", file=sys.stderr)
        sys.exit(1)

    # Dosyayı Kaydet
    with open(path, "w") as f:
        f.writelines(lines)

    print("[info] inject_namei: ZeroMount injected into namei.c ✅")
    sys.exit(0)

if __name__ == "__main__":
    main()
    
