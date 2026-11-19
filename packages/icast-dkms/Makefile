# Out-of-tree build for the SMIT iCast DVB-T2/C USB adapter (0x29df:0x0001).
#
# Only the two device modules are built. The in-tree dvb-core / dvb-usb /
# dvb-usb-v2 modules from the running kernel are used instead of rebuilding
# the vendor's bundled copies: dvb-usb-icast-smit links against the exported
# dvb_usb_* symbols of dvb-usb.ko, and dvb-usb-icast-fe provides the tuner
# frontend used by it.
#
# CachyOS kernels are built with clang; pass LLVM=1 to kbuild on those kernels
# or the GCC-only flags used by the kernel build will be rejected.

obj-m := dvb-usb-icast-fe.o dvb-usb-icast-smit.o

dvb-usb-icast-fe-objs := smit.o icast-fe.o
dvb-usb-icast-smit-objs := smit.o icast-smit.o

ccflags-y += -I$(src) -DCONFIG_DVB_NET

KDIR ?= /lib/modules/$(shell uname -r)/build

# Detect clang-built kernels (CachyOS, some Arch kernels).
LLVM_FLAG := $(shell grep -qs '^CONFIG_CC_IS_CLANG=y' $(KDIR)/include/config/auto.conf && echo LLVM=1)

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) $(LLVM_FLAG) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

.PHONY: all clean
