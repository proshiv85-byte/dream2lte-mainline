#!/usr/bin/env python3
"""Extract the Samsung DTBH image (dt.img) from a dream2lte boot.img.

S-Boot needs a valid DTBH in the boot image even though the mainline shim
ignores it: take it from the boot image of your current (vendor) kernel.

  tools/extract-dtbh.py stock-boot.img backup/dt-4.4.img
"""
import struct, sys

d = open(sys.argv[1], 'rb').read()
assert d[:8] == b'ANDROID!', 'not an Android boot image'
ksz, _, rsz, _, _, _, _, page, dsz = struct.unpack('<9I', d[8:44])
align = lambda x: (x + page - 1) // page * page
off = page + align(ksz) + align(rsz)
dt = d[off:off + dsz]
assert dt[:4] == b'DTBH', 'no DTBH image in this boot image'
open(sys.argv[2], 'wb').write(dt)
print(f'{sys.argv[2]}: {len(dt)} bytes')
