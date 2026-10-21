CROSS_COMPILE ?= aarch64-linux-gnu-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy

IMAGE ?= ../build/arch/arm64/boot/Image
DTB ?= ../build/arch/arm64/boot/dts/exynos/exynos8895-dream2lte.dtb
# Set DEV_RECOVERY=1 to make every reset of the new kernel boot TWRP
DEV_RECOVERY ?= 0

CPPFLAGS := -DIMAGE_PATH='"$(abspath $(IMAGE))"' -DDTB_PATH='"$(abspath $(DTB))"'
ifeq ($(DEV_RECOVERY),1)
CPPFLAGS += -DDEV_RECOVERY
endif

shim.bin: shim.elf
	$(OBJCOPY) -O binary $< $@

shim.elf: shim.S $(IMAGE) $(DTB) FORCE
	$(CC) $(CPPFLAGS) -nostdlib -static -Wl,-Ttext=0x80080000 -Wl,--build-id=none \
		-Wl,-e,_head -o $@ $<

clean:
	rm -f shim.elf shim.bin

.PHONY: clean FORCE
