#!/usr/bin/env python3
"""Check the 801SO NFC description in the akatsuki device trees.

usage: check_dt.py <Image.gz-dtb> <dtbo.img>

Every akatsuki DTB appended to Image.gz-dtb must describe the Sony CXD224x
(felica@29), the Rohm BD7602 (felica_ldo@1e) and felica,pm-ops with GPIO63
pulled up, and must not contain the NXP PN553. Every akatsuki overlay in
dtbo.img must carry felica@29 and no PN553 either. Needs dtc in PATH.
"""
import re
import struct
import subprocess
import sys
import tempfile
import zlib

FDT_MAGIC = b'\xd0\x0d\xfe\xed'
failures = 0


def check(cond, msg):
    global failures
    print(('PASS ' if cond else 'FAIL ') + msg)
    if not cond:
        failures += 1


def fdt_blobs(data):
    i = 0
    while True:
        i = data.find(FDT_MAGIC, i)
        if i < 0:
            return
        size, = struct.unpack('>I', data[i + 4:i + 8])
        if size < 64 or i + size > len(data):
            i += 4
            continue
        yield data[i:i + size]
        i += size


def decompile(blob):
    with tempfile.NamedTemporaryFile(suffix='.dtb') as f:
        f.write(blob)
        f.flush()
        return subprocess.run(['dtc', '-q', '-I', 'dtb', '-O', 'dts', f.name],
                              capture_output=True, text=True,
                              check=True).stdout


def has(dts, rx):
    return re.search(rx, dts, re.S) is not None


def main():
    kernel, dtbo = sys.argv[1], sys.argv[2]

    raw = open(kernel, 'rb').read()
    d = zlib.decompressobj(31)
    image = d.decompress(raw)
    m = re.search(rb'Linux version [^\n\0]+', image)
    print('     ' + (m.group().decode() if m else 'no version string'))

    total = aka = 0
    for blob in fdt_blobs(d.unused_data):
        total += 1
        dts = decompile(blob)
        m = re.search(r'model = "([^"]*)"', dts)
        model = m.group(1) if m else '?'
        if 'Akatsuki' not in model:
            continue
        aka += 1
        check(has(dts, r'felica@29 \{[^}]*compatible = "sony,cxd224x-i2c"'),
              '%s: felica@29 (sony,cxd224x-i2c)' % model)
        check(has(dts, r'felica_ldo@1e \{[^}]*compatible = "rohm,bd7602"'),
              '%s: felica_ldo@1e (rohm,bd7602)' % model)
        check(has(dts, r'compatible = "sony,cxd224x-pm-ops"'),
              '%s: felica,pm-ops' % model)
        check(not has(dts, r'nxp,pn553|pn553-pm-ops'),
              '%s: no nxp,pn553' % model)
        m = re.search(r'sdm_gpio_63 \{.*?config \{(.*?)\};', dts, re.S)
        check(m is not None and 'bias-pull-up' in m.group(1)
              and 'bias-pull-down' not in m.group(1),
              '%s: GPIO63 (FELICA_INT_N) pull-up' % model)
    check(aka > 0, 'appended DTBs: %d, akatsuki: %d' % (total, aka))

    total = aka = 0
    for blob in fdt_blobs(open(dtbo, 'rb').read()):
        total += 1
        dts = decompile(blob)
        if not has(dts, r'[Aa]katsuki'):
            continue
        aka += 1
        check(has(dts, r'felica@29 \{[^}]*compatible = "sony,cxd224x-i2c"'),
              'dtbo entry %d: felica@29' % total)
        check(not has(dts, r'nxp,pn553|pn553-pm-ops'),
              'dtbo entry %d: no nxp,pn553' % total)
    check(aka > 0, 'dtbo entries: %d, akatsuki: %d' % (total, aka))

    print('RESULT: ' + ('OK' if failures == 0 else '%d FAILURES' % failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
