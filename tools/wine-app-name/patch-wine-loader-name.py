#!/usr/bin/env python3
"""Create a per-app copy of the wine loader with a patched embedded Info.plist.

Wine's loader binary embeds an Info.plist (__TEXT,__info_plist) with
CFBundleName "Wine". Launch Services reads it at checkin and that becomes the
Dock tile / menu bar name — setProcessName cannot override it. ntdll also
re-execs the loader as "wine" by fixed name, so renaming the binary alone is
not enough: mage-wine's ntdll honors MAGE_APP_NAME and execs a same-named
sibling of the default loader instead (see dlls/ntdll/unix/loader.c).

This script creates that sibling: a copy of the loader with CFBundleName /
CFBundleExecutable / CFBundleIdentifier rewritten to the app name. The Mach-O
section size field is updated to fit the new plist (the section has file slack
after it).

Usage: patch-wine-loader-name.py <wine-prefix-install> <AppName> [bundle-id]
  <wine-prefix-install> = install root containing lib/wine/x86_64-unix/wine
Output: lib/wine/x86_64-unix/<AppName> next to the original loader.
Refreshes the copy when missing or older than the original loader.
"""
import os
import struct
import sys


def patch(src, dst, appname, bundleid):
    data = bytearray(open(src, 'rb').read())
    assert struct.unpack_from('<I', data, 0)[0] == 0xfeedfacf, "not a 64-bit Mach-O"
    ncmds = struct.unpack_from('<I', data, 16)[0]
    off = 32
    sect = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', data, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            nsects = struct.unpack_from('<I', data, off + 64)[0]
            so = off + 72
            for _ in range(nsects):
                if data[so:so + 16].split(b'\0')[0] == b'__info_plist':
                    sect = so
                    break
                so += 80
        off += cmdsize
    assert sect is not None, "no __info_plist section"
    size = struct.unpack_from('<Q', data, sect + 40)[0]
    foff = struct.unpack_from('<I', data, sect + 48)[0]
    xml = bytes(data[foff:foff + size])
    xml = xml.replace(b'<string>Wine</string>', f'<string>{appname}</string>'.encode())
    xml = xml.replace(b'<string>wine</string>', f'<string>{appname}</string>'.encode(), 1)
    xml = xml.replace(b'org.winehq.wine', bundleid.encode())
    assert foff + len(xml) <= len(data), "no file slack after __info_plist"
    data[foff:foff + len(xml)] = xml
    struct.pack_into('<Q', data, sect + 40, len(xml))
    with open(dst, 'wb') as f:
        f.write(bytes(data))
    os.chmod(dst, 0o755)


def main():
    install, appname = sys.argv[1], sys.argv[2]
    bundleid = sys.argv[3] if len(sys.argv) > 3 else \
        'app.mage.' + ''.join(c.lower() if c.isalnum() else '-' for c in appname).strip('-')
    loader = os.path.join(install, 'lib', 'wine', 'x86_64-unix', 'wine')
    dst = os.path.join(install, 'lib', 'wine', 'x86_64-unix', appname)
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(loader):
        print(f"up to date: {dst}")
        return
    patch(loader, dst, appname, bundleid)
    print(f"created: {dst} (bundle id {bundleid})")


if __name__ == '__main__':
    main()
