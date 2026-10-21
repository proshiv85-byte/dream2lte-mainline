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
 *   3. copies the DTB to DTB_DEST and the Image to IMAGE_DEST, then enters
 *      the kernel per Documentation/arch/arm64/booting.rst.
 *
 * The DTB handed over by S-Boot (at 0x8a000000) is ignored.
 */

#define IMAGE_DEST		0x80200000
#define DTB_DEST		0x8b000000

#define DECON_F_HW_SW_TRIG	0x12860070
#define DECON_TRIG_VAL		0x1281

#define PMU_INFORM2		0x16480808
#define PMU_INFORM3		0x1648080c
#define SEC_POWER_RESET		0x12345678
#define SEC_REASON_RECOVERY	0x12345674

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

	.ltorg

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
