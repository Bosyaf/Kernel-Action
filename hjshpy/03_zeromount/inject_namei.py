#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# inject_namei.py — inject ZeroMount hooks into fs/namei.c

import sys
import re

IDEMPOTENCY_MARKER = "#ifdef CONFIG_ZEROMOUNT"

INCLUDE_ANCHOR = '#include "mount.h"'
INCLUDE_INJECT = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "#include <linux/zeromount.h>\n"
    "#endif"
)

GETNAME_ANCHOR = r"(\tresult->uptr = filename;\s*\n\tresult->aname = NULL;\s*\n(?:.*\n)?\taudit_getname\(result\);\s*\n)"
GETNAME_INJECT = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "\tif (!IS_ERR(result)) {\n"
    "\t\tresult = zeromount_getname_hook(result);\n"
    "\t}\n"
    "#endif\n"
)

PERMISSION_INJECT = (
    "\t#ifdef CONFIG_ZEROMOUNT\n"
    "\tif (zeromount_is_injected_file(inode)) {\n"
    "\t\tif (mask & MAY_WRITE)\n"
    "\t\t\treturn -EACCES;\n"
    "\t\treturn 0;\n"
    "\t}\n"
    "\n"
    "\tif (S_ISDIR(inode->i_mode) && zeromount_is_traversal_allowed(inode, mask)) {\n"
    "\t\treturn 0;\n"
    "\t}\n"
    "\t#endif\n"
    "\n"
)

GENERIC_PERMISSION_ANCHOR = r"(int generic_permission\(struct user_namespace \*mnt_userns, struct inode \*inode, int mask\)\s*\{)"
INODE_PERMISSION_ANCHOR = r"(int inode_permission\(struct user_namespace \*mnt_userns, struct inode \*inode, int mask\)\s*\{)"

def find_anchor(lines, anchor, label):
    for i, line in enumerate(lines):
        if line == anchor:
            return i
    print(
        f"[error] inject_namei: anchor for {label} not found — "
        "upstream namei.c may have changed!",
        file=sys.stderr,
    )
    sys.exit(1)

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path/to/fs/namei.c>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]

    with open(path, "r") as f:
        content = f.read()

    if IDEMPOTENCY_MARKER in content:
        print("[info] inject_namei: ZeroMount already injected — skipping ✅")
        sys.exit(0)

    lines = content.splitlines(keepends=True)

    # 1. Include Eklemesi
    include_idx = find_anchor(lines, INCLUDE_ANCHOR + "\n", '#include "mount.h"')
    lines.insert(include_idx + 1, INCLUDE_INJECT + "\n")

    content = "".join(lines)

    # 2. getname_flags Kancası
    if not re.search(GETNAME_ANCHOR, content):
        print("[error] inject_namei: getname_flags() anchor not found!", file=sys.stderr)
        sys.exit(1)
    content = re.sub(GETNAME_ANCHOR, lambda m: m.group(1) + GETNAME_INJECT, content, count=1)

    # 3. generic_permission Kancası (Süslü parantezin hemen İÇİNE)
    if not re.search(GENERIC_PERMISSION_ANCHOR, content):
        print("[error] inject_namei: generic_permission() anchor not found!", file=sys.stderr)
        sys.exit(1)
    content = re.sub(GENERIC_PERMISSION_ANCHOR, lambda m: m.group(1) + "\n" + PERMISSION_INJECT, content, count=1)

    # 4. inode_permission Kancası (Süslü parantezin hemen İÇİNE)
    if not re.search(INODE_PERMISSION_ANCHOR, content):
        print("[error] inject_namei: inode_permission() anchor not found!", file=sys.stderr)
        sys.exit(1)
    content = re.sub(INODE_PERMISSION_ANCHOR, lambda m: m.group(1) + "\n" + PERMISSION_INJECT, content, count=1)

    with open(path, "w") as f:
        f.write(content)

    print("[info] inject_namei: ZeroMount injected into namei.c ✅")
    sys.exit(0)

if __name__ == "__main__":
    main()
    
