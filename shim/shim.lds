/* SPDX-License-Identifier: GPL-2.0 */
/*
 * All code and data first, the payload (DTB + Image) last: the Image is
 * copied/unpacked to IMAGE_DEST over the payload, so anything the shim still
 * needs afterwards (initrd.c's strings in .rodata, the stack) must lie
 * below it. Without a script, lld puts .rodata after the payload.
 */
OUTPUT_ARCH(aarch64)
ENTRY(_head)

SECTIONS
{
	. = 0x80080000;
	.text : {
		*(.text .text.*)	/* shim.S first: it holds the header */
		*(.rodata .rodata.*)
		*(.data .data.*)
		*(.bss .bss.* COMMON)
	}
	code_end = .;

	.payload : { *(.payload) }

	/DISCARD/ : { *(.eh_frame*) *(.comment) *(.note*) }
}

/* IMAGE_DEST in shim.S */
ASSERT(code_end <= 0x80200000, "shim code reaches into IMAGE_DEST")
