#!/usr/bin/env python3
"""Check the exported symbol CRC tables of vmlinux.

usage: check_kcrctab.py <vmlinux> <Module.symvers> [llvm-readelf]

With 32-bit CRCs every __kcrctab/__kcrctab_gpl entry is 4 bytes, there must
be no dynamic relocation inside those sections (a relocated CRC is corrupted
by the KASLR offset at boot) and every value must match Module.symvers.
"""
import re
import struct
import subprocess
import sys


def readelf(tool, vmlinux, *args):
    return subprocess.run([tool, '--wide', *args, vmlinux], check=True,
                          capture_output=True, text=True).stdout


def main():
    vmlinux, symvers = sys.argv[1], sys.argv[2]
    tool = sys.argv[3] if len(sys.argv) > 3 else 'llvm-readelf'

    secs = {}
    rx = re.compile(r'\s*\[\s*\d+\]\s+(\S+)\s+\S+\s+([0-9a-f]+)\s+'
                    r'([0-9a-f]+)\s+([0-9a-f]+)')
    for line in readelf(tool, vmlinux, '-S').splitlines():
        m = rx.match(line)
        if m:
            secs[m.group(1)] = tuple(int(x, 16) for x in m.groups()[1:])

    relocs = {}
    rx = re.compile(r'\s*([0-9a-f]{16})\s+[0-9a-f]+\s+(R_AARCH64_\w+)'
                    r'\s+(?:[0-9a-f]+\s+\S+\s*\+\s*)?([0-9a-f]+)?')
    for line in readelf(tool, vmlinux, '-r').splitlines():
        m = rx.match(line)
        if m:
            relocs[int(m.group(1), 16)] = (m.group(2),
                                           int(m.group(3) or '0', 16))

    want = {}
    for line in open(symvers):
        p = line.split('\t')
        if len(p) >= 2:
            want[p[1]] = int(p[0], 16)

    data = open(vmlinux, 'rb').read()

    def at(addr, n):
        for a, off, size in secs.values():
            if a and a <= addr < a + size:
                return data[off + addr - a:off + addr - a + n]
        raise ValueError('address %#x not in any section' % addr)

    def ptr(addr):
        r = relocs.get(addr)
        if r and r[0] == 'R_AARCH64_RELATIVE':
            return r[1]
        return struct.unpack('<Q', at(addr, 8))[0]

    def cstr(addr):
        b = at(addr, 256)
        return b[:b.index(b'\0')].decode()

    problems = total = 0
    for ksym, kcrc in (('__ksymtab', '__kcrctab'),
                       ('__ksymtab_gpl', '__kcrctab_gpl')):
        if kcrc not in secs:
            print('%s missing' % kcrc)
            problems += 1
            continue
        ca, _, cs = secs[kcrc]
        ka, _, ks = secs[ksym]
        n = ks // 16
        ent = cs // n if n else 0
        nrel = sum(1 for a in relocs if ca <= a < ca + cs)
        bad = 0
        for i in range(n):
            name = cstr(ptr(ka + 16 * i + 8))
            raw = at(ca + i * ent, ent)
            crc = struct.unpack('<I' if ent == 4 else '<Q', raw)[0]
            if name in want and want[name] != crc:
                bad += 1
                if bad <= 5:
                    print('   mismatch %s: %#x != %#x' % (name, crc,
                                                         want[name]))
        print('%-14s %5d entries, %d bytes each, %d relocations, '
              '%d mismatches' % (kcrc, n, ent, nrel, bad))
        problems += bad + nrel + (ent != 4)
        total += n

    print('RESULT: %s (%d symbols)' % ('OK' if not problems else 'PROBLEMS',
                                      total))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
