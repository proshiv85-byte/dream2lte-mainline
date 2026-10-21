#!/usr/bin/env python3
"""Pack a Samsung (header v0 + dt_size) boot.img for dream2lte.

S-Boot ignores the load addresses and the cmdline in the header: it copies
the kernel to 0x80080000, the ramdisk to 0x89000000 and the selected DTBH
entry to 0x8a000000.  The mainline shim ignores the ramdisk and DTB, but
S-Boot still needs a valid DTBH image to pick an entry from.
"""
import argparse, struct

PAGE = 2048

def align(b):
    return b + b'\0' * (-len(b) % PAGE)

ap = argparse.ArgumentParser()
ap.add_argument('--kernel', required=True)
ap.add_argument('--ramdisk')
ap.add_argument('--dt', required=True, help='Samsung DTBH image')
ap.add_argument('-o', '--output', required=True)
ap.add_argument('--max', type=int, default=40 * 1024 * 1024)
a = ap.parse_args()

kernel = open(a.kernel, 'rb').read()
ramdisk = open(a.ramdisk, 'rb').read() if a.ramdisk else b'\0' * 512
dt = open(a.dt, 'rb').read()
assert dt[:4] == b'DTBH', 'dt must be a DTBH image'

hdr = bytearray(PAGE)
hdr[0:8] = b'ANDROID!'
struct.pack_into('<10I', hdr, 8, len(kernel), 0x10008000, len(ramdisk),
                 0x11000000, 0, 0x10f00000, 0x10000100, PAGE, len(dt), 0)
hdr[48:64] = b'mainline'.ljust(16, b'\0')

img = bytes(hdr) + align(kernel) + align(ramdisk) + align(dt)
assert len(img) <= a.max, f'image too big: {len(img)} > {a.max}'
open(a.output, 'wb').write(img)
print(f'{a.output}: {len(img)} bytes')
