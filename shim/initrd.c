// SPDX-License-Identifier: GPL-2.0
/*
 * Hand S-Boot's ramdisk over to the kernel.
 *
 * S-Boot copies the boot.img ramdisk to 0x89000000 and puts its bounds into
 * /chosen of the DTB it passes (linux,initrd-start/-end). Our own DTB carries
 * both properties with zero values (added by the Makefile); copy S-Boot's
 * values into them when the ramdisk is real. Boot images without a ramdisk
 * carry a zero-filled dummy, which is left alone, so the kernel only uses its
 * built-in initramfs then.
 *
 * Runs with the MMU off: memory is Device memory, so no unaligned accesses
 * (-mstrict-align) and byte-wise big-endian reads.
 */

#define FDT_BEGIN_NODE	1
#define FDT_END_NODE	2
#define FDT_PROP	3
#define FDT_NOP		4
#define FDT_END		9

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long u64;

static u32 be32(const volatile u8 *p)
{
	return (u32)p[0] << 24 | (u32)p[1] << 16 | (u32)p[2] << 8 | p[3];
}

static int streq(const volatile u8 *a, const char *b)
{
	while (*a && *a == (u8)*b) {
		a++;
		b++;
	}
	return *a == (u8)*b;
}

static u32 slen(const volatile u8 *s)
{
	u32 n = 0;

	while (s[n])
		n++;
	return n;
}

/* the value of property @name of /chosen, its length in *len, or 0 */
static volatile u8 *chosen_prop(volatile u8 *fdt, const char *name, u32 *len)
{
	volatile u8 *p, *strings;
	int depth = 0, in_chosen = 0;

	if (be32(fdt) != 0xd00dfeed)
		return 0;
	p = fdt + be32(fdt + 8);		/* off_dt_struct */
	strings = fdt + be32(fdt + 12);		/* off_dt_strings */

	for (;;) {
		u32 tag = be32(p), plen;

		p += 4;
		switch (tag) {
		case FDT_BEGIN_NODE:
			depth++;
			if (depth == 2)
				in_chosen = streq(p, "chosen");
			p += (slen(p) + 4) & ~3u;
			break;
		case FDT_END_NODE:
			if (depth == 2)
				in_chosen = 0;
			depth--;
			break;
		case FDT_PROP:
			plen = be32(p);
			if (in_chosen && streq(strings + be32(p + 4), name)) {
				*len = plen;
				return p + 8;
			}
			p += 8 + ((plen + 3) & ~3u);
			break;
		case FDT_NOP:
			break;
		default:	/* FDT_END or garbage */
			return 0;
		}
	}
}

static u64 read_cells(const volatile u8 *v, u32 len)
{
	return len == 8 ? (u64)be32(v) << 32 | be32(v + 4) : be32(v);
}

static void write_cells(volatile u8 *v, u32 len, u64 val)
{
	u32 i;

	for (i = 0; i < len; i++)
		v[i] = val >> (8 * (len - 1 - i));
}

void initrd_handover(volatile u8 *ours, volatile u8 *sboot)
{
	volatile u8 *ss, *se, *os, *oe;
	u32 ssl, sel, osl, oel;
	u64 start, end;

	ss = chosen_prop(sboot, "linux,initrd-start", &ssl);
	se = chosen_prop(sboot, "linux,initrd-end", &sel);
	os = chosen_prop(ours, "linux,initrd-start", &osl);
	oe = chosen_prop(ours, "linux,initrd-end", &oel);
	if (!ss || !se || !os || !oe || osl != 8 || oel != 8 ||
	    (ssl != 4 && ssl != 8) || (sel != 4 && sel != 8))
		return;

	start = read_cells(ss, ssl);
	end = read_cells(se, sel);
	/* no ramdisk, or the zero-filled dummy */
	if (end <= start || !*(volatile u8 *)start)
		return;

	write_cells(os, 8, start);
	write_cells(oe, 8, end);
}
