/*
 * kfw IMAGE NAME OUT: copy the firmware NAME that a Samsung 4.4 kernel has
 * built in (CONFIG_FIRMWARE_IN_KERNEL) out of the boot image IMAGE.
 *
 * Writes every candidate as OUT.0, OUT.1, ... and prints their number; the
 * caller checks which one has the expected sha256. The kernel's builtin_fw
 * table holds {name, data, size} pointers; an uncompressed arm64 4.4 Image
 * (what Samsung boot images carry) is linked at KERNEL_BASE, so the entry is
 * found from the name string alone.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define KERNEL_BASE	0xffffff8008080000ULL

static uint32_t le32(const unsigned char *p)
{
	return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
}

static uint64_t le64(const unsigned char *p)
{
	return le32(p) | (uint64_t)le32(p + 4) << 32;
}

int main(int argc, char **argv)
{
	unsigned char hdr[48], *k, *n;
	uint32_t ksize, page;
	size_t namelen, i;
	uint64_t name_va;
	int count = 0;
	FILE *f;

	if (argc != 4) {
		fprintf(stderr, "usage: kfw IMAGE NAME OUT\n");
		return 2;
	}
	f = fopen(argv[1], "rb");
	if (!f || fread(hdr, 1, sizeof(hdr), f) != sizeof(hdr) || memcmp(hdr, "ANDROID!", 8)) {
		fprintf(stderr, "kfw: %s: not a boot image\n", argv[1]);
		return 1;
	}
	ksize = le32(hdr + 8);
	page = le32(hdr + 36);
	k = malloc(ksize);
	if (!k || fseek(f, page, SEEK_SET) || fread(k, 1, ksize, f) != ksize) {
		fprintf(stderr, "kfw: cannot read the kernel\n");
		return 1;
	}
	fclose(f);

	namelen = strlen(argv[2]) + 1;	/* with the NUL */
	n = memmem(k, ksize, argv[2], namelen);
	if (!n) {
		printf("0\n");
		return 0;
	}
	name_va = KERNEL_BASE + (n - k);
	for (i = 0; i + 24 <= ksize; i += 8) {
		uint64_t data, size;
		char out[512];
		FILE *o;

		if (le64(k + i) != name_va)
			continue;
		data = le64(k + i + 8) - KERNEL_BASE;
		size = le64(k + i + 16);
		if (data >= ksize || size == 0 || size > ksize - data)
			continue;
		snprintf(out, sizeof(out), "%s.%d", argv[3], count);
		o = fopen(out, "wb");
		if (!o || fwrite(k + data, 1, size, o) != size || fclose(o)) {
			fprintf(stderr, "kfw: cannot write %s\n", out);
			return 1;
		}
		count++;
	}
	printf("%d\n", count);
	return 0;
}
