#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# inject_namei.py — inject ZeroMount hooks into fs/namei.c
#
# Handles namei.c injection for every ZeroMount build (RESUKISU, SUKISU,
# KSUNEXT — ZeroMount requires SuSFS, so VANILLA is never a valid combo,
# see zeromount.sh), replacing the namei.c hunks from the ZeroMount patch,
# which are diffed against a SuSFS-patched baseline and mis-apply on a
# non-SuSFS tree (see strip_namei_hunk.py for the full explanation). The
# ZeroMount patch is pre-stripped of its namei.c hunks before being
# applied, so this worker is always the sole authority for namei.c
# injection.

import sys

IDEMPOTENCY_MARKER = "#ifdef CONFIG_ZEROMOUNT"

INCLUDE_ANCHOR = '#include "mount.h"'
INCLUDE_INJECT = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "#include <linux/zeromount.h>\n"
    "#endif"
)

GETNAME_INJECT = (
    "\n"
    "\t#ifdef CONFIG_ZEROMOUNT\n"
    "\tif (!IS_ERR(result)) {\n"
    "\t\tresult = zeromount_getname_hook(result);\n"
    "\t}\n"
    "\t#endif\n"
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
)

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path/to/fs/namei.c>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]

    with open(path, "r") as f:
        content = f.read()

    # Idempotency check (Zaten yamalandıysa atla)
    if IDEMPOTENCY_MARKER in content:
        print("[info] inject_namei: ZeroMount already injected — skipping ✅")
        sys.exit(0)

    # 1. Inject #include <linux/zeromount.h>
    idx = content.find(INCLUDE_ANCHOR)
    if idx == -1:
        print("[error] inject_namei: include anchor not found!", file=sys.stderr)
        sys.exit(1)
    end_idx = content.find('\n', idx)
    content = content[:end_idx+1] + INCLUDE_INJECT + "\n" + content[end_idx+1:]

    # 2. Inject zeromount_getname_hook in getname_flags()
    func_idx = content.find('getname_flags(')
    if func_idx == -1:
        print("[error] inject_namei: getname_flags() not found!", file=sys.stderr)
        sys.exit(1)
    audit_idx = content.find('audit_getname(result);', func_idx)
    if audit_idx == -1:
        print("[error] inject_namei: audit_getname(result) anchor not found inside getname_flags!", file=sys.stderr)
        sys.exit(1)
    end_idx = content.find('\n', audit_idx)
    content = content[:end_idx+1] + GETNAME_INJECT + content[end_idx+1:]

    # 3. Inject permission short-circuit into generic_permission() (Süslü Parantez İçine)
    func_idx = content.find('generic_permission(')
    if func_idx == -1:
        print("[error] inject_namei: generic_permission() not found!", file=sys.stderr)
        sys.exit(1)
    brace_idx = content.find('{', func_idx)
    if brace_idx == -1:
        print("[error] inject_namei: '{' not found for generic_permission!", file=sys.stderr)
        sys.exit(1)
    end_idx = content.find('\n', brace_idx)
    content = content[:end_idx+1] + PERMISSION_INJECT + "\n" + content[end_idx+1:]

    # 4. Inject permission short-circuit into inode_permission() (Süslü Parantez İçine)
    func_idx = content.find('inode_permission(')
    if func_idx == -1:
        print("[error] inject_namei: inode_permission() not found!", file=sys.stderr)
        sys.exit(1)
    brace_idx = content.find('{', func_idx)
    if brace_idx == -1:
        print("[error] inject_namei: '{' not found for inode_permission!", file=sys.stderr)
        sys.exit(1)
    end_idx = content.find('\n', brace_idx)
    content = content[:end_idx+1] + PERMISSION_INJECT + "\n" + content[end_idx+1:]

    with open(path, "w") as f:
        f.write(content)

    print("[info] inject_namei: ZeroMount injected into namei.c ✅")
    sys.exit(0)

if __name__ == "__main__":
    main()
    
