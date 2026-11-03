CROSS_COMPILE ?= aarch64-linux-gnu-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy

IMAGE ?= ../build/arch/arm64/boot/Image
DTB ?= ../build/arch/arm64/boot/dts/exynos/exynos8895-dream2lte.dtb
# Set DEV_RECOVERY=1 to make every reset of the new kernel boot TWRP
DEV_RECOVERY ?= 0
# Set LZ4=1 to carry the Image LZ4-compressed (needs the lz4 tool)
LZ4 ?= 0

ifeq ($(LZ4),1)
PAYLOAD := Image.lz4
CPPFLAGS := -DLZ4_IMAGE
else
PAYLOAD := $(IMAGE)
endif
CPPFLAGS += -DIMAGE_PATH='"$(abspath $(PAYLOAD))"' -DDTB_PATH='"$(abspath shim.dtb)"'
CFLAGS := -O2 -ffreestanding -fno-builtin -fno-stack-protector -fno-pic \
	-mgeneral-regs-only -mstrict-align -fno-asynchronous-unwind-tables -Wall
ifeq ($(DEV_RECOVERY),1)
CPPFLAGS += -DDEV_RECOVERY
endif

shim.bin: shim.elf
	$(OBJCOPY) -O binary $< $@

# the DTB with zero linux,initrd-start/-end for initrd.c to fill in
shim.dtb: $(DTB) FORCE
	cp $< $@
	fdtput -t x $@ /chosen linux,initrd-start 0 0
	fdtput -t x $@ /chosen linux,initrd-end 0 0

Image.lz4: $(IMAGE) FORCE
	lz4 -q -l -9 -f $< $@

shim.elf: shim.S initrd.c lz4.c shim.lds shim.dtb $(PAYLOAD) FORCE
	$(CC) $(CPPFLAGS) $(CFLAGS) -nostdlib -static -Wl,-T,shim.lds \
		-Wl,--build-id=none -o $@ shim.S initrd.c lz4.c

clean:
	rm -f shim.elf shim.bin shim.dtb Image.lz4

.PHONY: clean FORCE
