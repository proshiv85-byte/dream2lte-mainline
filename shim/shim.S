/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Minimal boot shim for Samsung Galaxy S8+ (dream2lte, Exynos 8895).
 *
 * S-Boot copies the boot.img "kernel" to 0x80080000 and jumps to it with the
 * MMU off.  A mainline arm64 Image must sit on a 2 MiB boundary, so this shim
 * is what S-Boot loads; it carries the real Image and its DTB and:
 *
 *   1. sets the DECON-F HW/SW trigger control so the bootloader framebuffer
 *      (simple-framebuffer at 0xcc000000) keeps being scanned out,
 *   2. optionally (DEV_RECOVERY) presets the Samsung reboot reason to
 *      "recovery", so any reset of the new kernel lands in TWRP,
 *   3. copies the DTB to DTB_DEST and the Image to IMAGE_DEST (with
 *      LZ4_IMAGE, the Image is LZ4-compressed: moved to LZ4_SCRATCH first,
 *      then decompressed to IMAGE_DEST by lz4.c),
 *   4. copies S-Boot's boot mode (the value of "androidboot.mode=" in the
 *      bootargs of the DTB S-Boot hands over, e.g. "charger" when a cable
 *      powered the phone on) into the placeholder of /chosen/
 *      dream2lte,sboot-mode in our DTB, or "none" (no androidboot.mode),
 *      or "no-dtb" (no DTB found), for the initramfs,
 *   5. hands S-Boot's ramdisk (if the boot.img has a real one) over to the
 *      kernel, see initrd.c,
 *   6. enters the kernel per Documentation/arch/arm64/booting.rst.
 *
 * Otherwise the DTB handed over by S-Boot (at 0x8a000000) is ignored.
 */

#define IMAGE_DEST		0x80200000
#define DTB_DEST		0x8b000000
/* above the decompressed Image and its BSS, below S-Boot's ramdisk */
#define LZ4_SCRATCH		0x84000000

#define DECON_F_HW_SW_TRIG	0x12860070
#define DECON_TRIG_VAL		0x1281

#define PMU_INFORM2		0x16480808
#define PMU_INFORM3		0x1648080c
#define SEC_POWER_RESET		0x12345678
#define SEC_REASON_RECOVERY	0x12345674

/* FDT magic 0xd00dfeed as a little-endian word, and a bound for the search */
#define SBOOT_DTB		0x8a000000
#define FDT_MAGIC_LE		0xedfe0dd0
#define SBOOT_DTB_MAX		0x200000
/* room for the mode in the placeholder, with its NUL */
#define MODE_MAX		31

	.text
	.globl	_head
_head:
	/* arm64 Image header, so S-Boot treats us like any other kernel */
	b	start			/* code0 */
	.long	0			/* code1 */
	.quad	0x80000			/* text_offset */
	.quad	_end - _head		/* image_size */
	.quad	0xa			/* flags: LE, 4K pages */
	.quad	0, 0, 0			/* res2-res4 */
	.ascii	"ARM\x64"		/* magic */
	.long	0			/* res5 */

start:
	/* a stack for initrd.c, inside the shim below IMAGE_DEST */
	adrp	x4, stack_top
	add	x4, x4, :lo12:stack_top
	mov	sp, x4

	ldr	x4, =DECON_F_HW_SW_TRIG
	ldr	w5, =DECON_TRIG_VAL
	str	w5, [x4]

#ifdef DEV_RECOVERY
	ldr	x4, =PMU_INFORM2
	ldr	w5, =SEC_POWER_RESET
	str	w5, [x4]
	ldr	x4, =PMU_INFORM3
	ldr	w5, =SEC_REASON_RECOVERY
	str	w5, [x4]
#endif

	/* DTB -> DTB_DEST (forward copy, regions are disjoint) */
	adrp	x4, dtb_start
	add	x4, x4, :lo12:dtb_start
	adrp	x5, dtb_end
	add	x5, x5, :lo12:dtb_end
	ldr	x6, =DTB_DEST
1:	ldp	x7, x8, [x4], #16
	stp	x7, x8, [x6], #16
	cmp	x4, x5
	b.lo	1b

#ifdef LZ4_IMAGE
	/* compressed Image -> LZ4_SCRATCH (disjoint, forward copy) */
	adrp	x4, image_start
	add	x4, x4, :lo12:image_start
	adrp	x5, image_end
	add	x5, x5, :lo12:image_end
	ldr	x6, =LZ4_SCRATCH
2:	ldp	x7, x8, [x4], #16
	stp	x7, x8, [x6], #16
	cmp	x4, x5
	b.lo	2b

	/* lz4_unpack(LZ4_SCRATCH, length, IMAGE_DEST); hang if not LZ4 */
	adrp	x4, image_start
	add	x4, x4, :lo12:image_start
	sub	x1, x5, x4
	ldr	x0, =LZ4_SCRATCH
	ldr	x2, =IMAGE_DEST
	bl	lz4_unpack
5:	cbz	x0, 5b
#else
	/*
	 * Image -> IMAGE_DEST.  The destination lies above the source and
	 * the two may overlap, so copy backwards.
	 */
	adrp	x4, image_start
	add	x4, x4, :lo12:image_start
	adrp	x5, image_end
	add	x5, x5, :lo12:image_end
	ldr	x6, =IMAGE_DEST
	sub	x7, x5, x4
	add	x6, x6, x7
2:	ldp	x7, x8, [x5, #-16]!
	stp	x7, x8, [x6, #-16]!
	cmp	x5, x4
	b.hi	2b
#endif

	bl	sboot_mode

	ldr	x0, =DTB_DEST
	ldr	x1, =SBOOT_DTB
	bl	initrd_handover

	/* The copied code must not be fetched through stale I-cache lines */
	dsb	sy
	ic	iallu
	dsb	sy
	isb

	ldr	x0, =DTB_DEST
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	ldr	x4, =IMAGE_DEST
	br	x4

/*
 * memfind: x0 haystack, x1 its length, x2 needle, x3 needle length (> 0).
 * Returns the first match in x0, or 0. Byte accesses only: the MMU is off,
 * so memory is Device memory and unaligned word accesses would fault.
 */
memfind:
	cmp	x1, x3
	b.lo	3f
	sub	x1, x1, x3
	add	x4, x0, x1		/* last possible start */
1:	mov	x5, xzr
2:	ldrb	w6, [x0, x5]
	ldrb	w7, [x2, x5]
	cmp	w6, w7
	b.ne	4f
	add	x5, x5, #1
	cmp	x5, x3
	b.lo	2b
	ret
4:	add	x0, x0, #1
	cmp	x0, x4
	b.ls	1b
3:	mov	x0, xzr
	ret

/* step 4 above; uses x19-x22. S-Boot's DTB is always at SBOOT_DTB. */
sboot_mode:
	mov	x22, x30
	ldr	x0, =DTB_DEST
	adrp	x1, dtb_start
	add	x1, x1, :lo12:dtb_start
	adrp	x2, dtb_end
	add	x2, x2, :lo12:dtb_end
	sub	x1, x2, x1
	adr	x2, placeholder
	mov	x3, #(placeholder_end - placeholder)
	bl	memfind
	cbz	x0, 9f			/* DTB without the placeholder */
	mov	x20, x0

	adr	x21, mode_nodtb
	ldr	x19, =SBOOT_DTB
	ldr	w4, [x19]
	ldr	w5, =FDT_MAGIC_LE
	cmp	w4, w5
	b.ne	6f
	adr	x21, mode_none
	ldr	w1, [x19, #4]		/* totalsize, big-endian */
	rev	w1, w1
	ldr	x4, =SBOOT_DTB_MAX
	cmp	x1, x4
	csel	x1, x1, x4, ls
	mov	x0, x19
	adr	x2, mode_key
	mov	x3, #(mode_key_end - mode_key)
	bl	memfind
	cbz	x0, 6f
	add	x21, x0, #(mode_key_end - mode_key)

	/* copy up to a space or NUL, at most MODE_MAX bytes, then a NUL */
6:	mov	x5, xzr
7:	ldrb	w6, [x21, x5]
	cmp	w6, #' '
	b.ls	8f
	strb	w6, [x20, x5]
	add	x5, x5, #1
	cmp	x5, #MODE_MAX
	b.lo	7b
8:	strb	wzr, [x20, x5]
9:	ret	x22

	.ltorg

placeholder:
	.ascii	"@D2L-SBOOT-MODE@"
placeholder_end:
mode_key:
	.ascii	"androidboot.mode="
mode_key_end:
mode_none:
	.asciz	"none"
mode_nodtb:
	.asciz	"no-dtb"

	.balign	16
stack:
	.space	4096
stack_top:

	/* the payload goes after all code, initrd.c included */
	.section .payload, "a"
	.balign	16
dtb_start:
	.incbin	DTB_PATH
	.balign	16
dtb_end:

	.balign	4096
image_start:
	.incbin	IMAGE_PATH
	.balign	16
image_end:
_end:
