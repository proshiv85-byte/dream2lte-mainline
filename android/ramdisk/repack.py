#!/usr/bin/env python3
"""Replace or add files in a gzipped newc cpio ramdisk without unpacking it.

  repack.py <in.cpio.gz> <out.cpio.gz> <name>=<file> [...]

Added files are regular files owned by root, mode 0644 (0640 for fstab*,
like the stock one). Other entries, device nodes included, are kept as is.
"""
import gzip, sys

def entries(data):
    off = 0
    while True:
        assert data[off:off + 6] == b'070701', 'not a newc cpio archive'
        f = [int(data[off + 6 + i * 8:off + 14 + i * 8], 16) for i in range(13)]
        namesize, filesize = f[11], f[6]
        name = data[off + 110:off + 110 + namesize - 1].decode()
        hdr_end = (off + 110 + namesize + 3) & ~3
        end = (hdr_end + filesize + 3) & ~3
        if name == 'TRAILER!!!':
            return
        yield name, data[off:end]
        off = end

def newc(name, mode, body, ino):
    n = name.encode() + b'\0'
    fields = [ino, mode, 0, 0, 1, 0, len(body), 0, 0, 0, 0, len(n), 0]
    h = b'070701' + b''.join(b'%08X' % v for v in fields) + n
    h += b'\0' * (-len(h) % 4)
    return h + body + b'\0' * (-len(body) % 4)

src, dst, repl = sys.argv[1], sys.argv[2], dict(a.split('=', 1) for a in sys.argv[3:])
data = gzip.decompress(open(src, 'rb').read())
out, ino = [], 0x7000
for name, raw in entries(data):
    if name not in repl:
        out.append(raw)
for name, path in repl.items():
    body = open(path, 'rb').read()
    out.append(newc(name, 0o100640 if name.startswith('fstab') else 0o100644, body, ino))
    ino += 1
out.append(newc('TRAILER!!!', 0, b'', 0))
open(dst, 'wb').write(gzip.compress(b''.join(out), 9))
