
INCLUDES=
DEFINES=-D__KERNEL__ -DMODULE -DEXPORT_SYMTABS
CFLAGS=$(DEFINES) $(INCLUDES) -fomit-frame-pointer
# the netwide assembler
NASM=nasm

default:
	@echo "Suggested usage:"
	@echo "    make INCLUDES=-I/path/to/kernel/include all"

all: strap.o ribbon.bin

strap.o: strap.c
	$(CC) -c strap.c $(CFLAGS) -o strap.o

%.bin: %.s
	$(NASM) $< -o $@

clean:
	rm -f *~
