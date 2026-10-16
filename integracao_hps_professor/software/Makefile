CC ?= gcc
CFLAGS ?= -O2 -std=c99 -Wall -Wextra -Werror
LDLIBS ?= -lrt
TARGET := $(shell $(CC) -dumpmachine)
ARM_SRC := $(if $(findstring arm,$(TARGET)),mmio_arm.S,)
all: gpuctl
gpuctl: gpuctl.c mailbox.c scene.c mailbox.h scene.h $(ARM_SRC)
	$(CC) $(CFLAGS) gpuctl.c mailbox.c scene.c $(ARM_SRC) -o $@ $(LDLIBS)
test: test_mailbox test_cli
	./test_mailbox
	./test_cli
test_mailbox: test_mailbox.c mailbox.c scene.c mailbox.h scene.h
	$(CC) $(CFLAGS) test_mailbox.c mailbox.c scene.c -o $@
test_cli: test_cli.c gpuctl.c mailbox.c scene.c mailbox.h scene.h $(ARM_SRC)
	$(CC) $(CFLAGS) test_cli.c mailbox.c scene.c $(ARM_SRC) -o $@ $(LDLIBS)
.PHONY: all test
