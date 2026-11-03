// SPDX-License-Identifier: GPL-2.0
/*
 * LZ4 legacy-format decompressor (what "lz4 -l" writes) for the boot shim:
 * a postmarketOS kernel doesn't fit the 40 MiB BOOT partition uncompressed.
 *
 * Runs with the MMU off: memory is Device memory, so byte accesses only.
 */

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long u64;

#define LZ4_LEGACY_MAGIC	0x184c2102

static u32 le32(const volatile u8 *p)
{
	return p[0] | (u32)p[1] << 8 | (u32)p[2] << 16 | (u32)p[3] << 24;
}

static volatile u8 *lz4_block(const volatile u8 *ip, const volatile u8 *iend,
			      volatile u8 *op)
{
	while (ip < iend) {
		u32 token = *ip++, len, off, b;
		const volatile u8 *match;

		len = token >> 4;
		if (len == 15) {
			do {
				b = *ip++;
				len += b;
			} while (b == 255);
		}
		while (len--)
			*op++ = *ip++;
		if (ip >= iend)		/* the last sequence has no match */
			break;

		off = ip[0] | ip[1] << 8;
		ip += 2;
		len = token & 15;
		if (len == 15) {
			do {
				b = *ip++;
				len += b;
			} while (b == 255);
		}
		len += 4;
		match = op - off;
		while (len--)
			*op++ = *match++;
	}
	return op;
}

/* returns the end of the output, or 0 if @src isn't LZ4 legacy data */
volatile u8 *lz4_unpack(const volatile u8 *src, u64 len, volatile u8 *dst)
{
	const volatile u8 *end = src + len;

	if (len < 4 || le32(src) != LZ4_LEGACY_MAGIC)
		return 0;
	src += 4;
	while (end - src >= 4) {
		u32 size = le32(src);

		/* concatenated streams, or the padding after the last block */
		if (size == LZ4_LEGACY_MAGIC) {
			src += 4;
			continue;
		}
		src += 4;
		if (!size || size > (u64)(end - src))
			break;
		dst = lz4_block(src, src + size, dst);
		src += size;
	}
	return dst;
}
