
	;;
	;; debugging ribbon
	;; Julian Squires <tek@wiw.org> / 2000
	;;

	;; change this if STRAP_CODELEN in strap.c is ever changed!
	;; (it should be 0x1000-STRAP_CODELEN)
	org 0x0c00

	;; 
	;; main function (must come first)
	;; 
main:
	;; setup a stack
	mov ax, stackSegment
	mov es, ax
	mov sp, stackTop

	;; reenable interrupts
	sti

	;; reset to a known text mode
	call videoReset
	call dot

	;; unmask IRQs
	call picReset
	call dot

	;; reset the timer
	call pitReset
	call dot

	;;
	;; keyboard:
	;;     reset keyboard
	;;     test keyboard
	;;     disable A20 gating
	;;
	;call kbdTest
	;call dot
	call kbdReset
	call dot
	;call kbdTest
	;call dot
	call kbdDisableA20
	call dot

	;; reset the disk drives
	call diskReset
	call dot

	;; load bootblock into 0000:7C00
	mov di, bootLocation
	mov si, bootblock
	mov ax, cs
	mov ds, ax
	mov es, ax
	mov cx, bootblockLen
	rep movsb
	call dot

	;; let's try our own keyboard handler
	mov ax, 0x0
	mov ds, ax
	mov es, ax
	mov si, 9*4
	mov di, si
	lodsd
	mov ebx, eax
	mov eax, handleInt9
	stosd
	mov ax, cs
	mov es, ax
	mov di, oldInt9
	mov eax, ebx
	stosd

	;; this will hang until we fix keyboard
	xor ax, ax
	int 0x16

	;;
	;; use the bios to reset state
	;;

	;; preserve memory
	mov ax, biosSegment
	mov es, ax
	mov si, 0x0072
	;; tell the BIOS to preserve our memory (don't wipe)
	mov ax, 0x4321
	stosw
	mov si, 0x0067
	;; OLD
	;; jump back to 0000:7C00 when we finish (write 7c00 into 40:67)
	;;mov eax, bootLocation
	;; NEW
	;; jump ahead when we finish
	mov eax, afterReset
	stosd
	;; write into CMOS RAM that we want to go to [40:67]
	cli
	mov al, 0x0F
	or al, 0x80
	out cmosIndexRegister, al
	call ioDelay
	;; change this to boot in different manners
 	;; 0x04 will read floppy then hdd
	;; 0x05 will flush keyboard buffer, do an EOI, then jump to [40:67]
	;;                                  [End Of Interrupt, see pokepic]
	;; 0x0a will jump to our own code without the above
	mov al, 0x05
	out cmosDataRegister, al
	call ioDelay
	mov al, 0x00
	out cmosIndexRegister, al
	call ioDelay
	sti
	;; reset with the keyboard controller
	;; (slower than triple fault, but triple fault requires
	;;  modification of strap.c)
	;; note FE pulses bit 0 (cpu reset), because zero == pulse bit,
	;; while one == don't pulse.
	mov al, kbdPulseCtrlCommand | ~(0x1)
	out kbdControlRegister, al
	call ioDelay

	;; we should never get here
	;; normal reset
	jmp 0xFFFF:0x0000

afterReset:
	call dot

	;; tell the system to boot from the hard drive
	;; (dx = 0x0000 for floppy drive, 0x0080 for hard drive)
	mov dx, 0x0080

	;; jump directly to bootblock
	jmp 0x0:0x7c00

	;; end of main function


	;; 
	;; helper procedures
	;;


	;; output . to screen
dot:
	mov al, '.'
	call putc
	ret

	;;
	;; dumpdword
	;; output the dword passed in eax
	;; 
dumpdword:
	push eax
	shr eax, 16
	call dumpword
	pop eax
	call dumpword
	ret

	;;
	;; dumpword
	;; output the word passed in ax
	;; 
dumpword:
	push ax

	call dumpbyte
	mov ah, al
	call dumpbyte

	pop ax
	ret

	;;
	;; dumpbyte
	;; output the byte passed in ah
	;; 
dumpbyte:
	push ax
	push bx
	push cx

	xor bx, bx
	mov cx, ax
	push cx
	shr ch, 0x04
	mov al, ch
	call hexal
	call putc
	pop cx
	mov al, ch
	and al, 0x0F
	call hexal
	call putc

	pop cx
	pop bx
	pop ax
	ret

	;; put character in al on the screen
putc:	push ax
	push bx

	xor bx, bx
	mov ah, 0x0E
	int 0x10

	pop bx
	pop ax
	ret

	;;
	;; hexal
	;; convert al (0 <= al <= 15) to ASCII hex
	;; 
hexal:	cmp al, 9
	jg .l1
	add al, '0'
	ret
.l1:	add al, 'a'-10
	ret

	;;
	;; Bring the 8259 PIC to as sane a state as possible
	;; note that there is more that could be done - one could
	;; send the ICWs (initialization control words), but
	;; for the moment we rely on the BIOS to do this
	;; 
picReset:
	push ax

	cli
	;; unmask all the IRQs just to be safe
	mov al, 0x0
	out picMasterMaskRegister, al
	call ioDelay
	out picSlaveMaskRegister, al
	call ioDelay

	;; send EOI (interrupt finished) to PIC, just in case Linux left an
	;; int ``with its pants down'', as it were
	;; reason this is commented out: the bios should do this for us
	;;mov al, picEndOfInterrupt
	;;out picMasterCommandRegister, al
	;;call ioDelay
	;;out picSlaveCommandRegister, al
	;;call ioDelay

	sti

	pop ax
	ret

	;;
	;; bring the video card to a known state (80x25 text mode)
	;; uses the video bios
	;;
videoReset:
	push ax
	mov ax, 0x0003
	int 0x10
	pop ax
	ret

	;; io delay
ioDelay:
	;; old way:
	;;jmp short $+2
	;; new way: (as seen in Robert Collins' fu on x86.org)
	out 0xED, ax
	ret

	;;
	;; reset the 825[34] PIT (Programmable Interval Timer),
	;; 
pitReset:
	push ax

	cli
	mov al, 0x36
	out 0x43, al
	call ioDelay
	xor al, al
	out 0x40, al
	call ioDelay
	out 0x40, al
	call ioDelay
	sti

	pop ax
	ret

	;;
	;; reset the 8042 as best we can
	;; 
kbdReset:
	push ax

	;; explicitly enable the keyboard
	mov al, kbdResetToDefaultCommand
	out kbdDataRegister, al
	call ioDelay
	call kbdWaitForACK
	jnc .l1
	;; an error occurred
	mov al, '#'
	call putc
.l1:
	;; reset the keyboard
	mov al, kbdResetToDefaultCommand
	out kbdDataRegister, al
	call ioDelay
	call kbdWaitForACK
	jnc .l2
	;; an error occurred
	mov al, '$'
	call putc
.l2:
	pop ax
	ret

kbdWaitForOutput:
.l1:	in al, kbdControlRegister
	test al, 0x01
	jz .l1
	ret

	;; sets carry on error
kbdWaitForACK:
	clc
	call kbdWaitForOutput
	in al, kbdDataRegister
	cmp al, kbdDataACK
	je .l1
	stc
.l1:	ret

	;; perform self-tests
kbdTest:
	push ax

	;; keyboard self-test (as opposed to the keyboard interface)
	mov al, kbdSelfTestCtrlCommand
	out kbdControlRegister, al
	call ioDelay
	call kbdWaitForOutput
	in al, kbdDataRegister
	cmp al, 0x55
	je .l1
	;; uh oh, the self-test failed, dump some debugging info
	mov ah, al
	call dumpbyte
	mov al, '!'
	call putc
.l1:
	;; interface self-test
	mov al, kbdInterfaceSelfTestCtrlCommand
	out kbdControlRegister, al
	call ioDelay
	call kbdWaitForOutput
	in al, kbdDataRegister
	jnz .l2
	mov ah, al
	call dumpbyte
	mov al, '@'
	call putc
.l2:
	pop ax
	ret

	;; disable the A20 line
kbdDisableA20:
	push ax

	mov al, kbdReadOutputPortCtrlCommand
	out kbdControlRegister, al
	call ioDelay
	in al, kbdDataRegister
	mov ah, al
	mov al, kbdWriteOutputPortCtrlCommand
	out kbdControlRegister, al
	call ioDelay
	mov al, 0xDD		; FIXME
	out kbdDataRegister, al
	call ioDelay

	pop ax
	ret

	;; reset floppy and hard drive systems via the bios
diskReset:
	;; reset the floppy disk system
	mov ax, 0x0000
	int 0x13

	;; reset the first hard drive
	mov ax, 0x0D80
	int 0x13
	ret

	;;
	;; faux int9 handler for testing
	;;
handleInt9:
	cli
	mov ax, videoSegment
	mov es, ax
	mov di, 0x0
	in al, kbdDataRegister
	mov ah, 0x01
	mov bh, al
	shr al, 4
	call hexal
	stosw
	mov al, bh
	and al, 0x0F
	call hexal
	stosw
	;; send end of interrupt
	mov al, 0x20
	out picMasterCommandRegister, al
	sti
	ret

	;; end of helper procedures

	;;
	;; data
	;;

oldInt9	resd 1

	;; end of data declarations

	;;
	;; constants
	;;

videoSegment		equ 0xb800
stackSegment		equ 0x2000 ; arbitrary
stackTop		equ 0xF000

	;; bootstrap related
bootLocation		equ 0x00007c00
bootblockLen		equ 0x0200
cmosIndexRegister	equ 0x70
cmosDataRegister	equ 0x71
biosSegment		equ 0x0040

	;; PIC related
picMasterMaskRegister	equ 0x21
picSlaveMaskRegister	equ 0xA1
picMasterCommandRegister	equ 0x20
picSlaveCommandRegister		equ 0xA0

	;; keyboard related
kbdControlRegister	equ 0x64
kbdDataRegister		equ 0x60

kbdReadModeCtrlCommand	equ 0x20
kbdWriteModeCtrlCommand	equ 0x60
kbdSelfTestCtrlCommand		equ 0xAA
kbdInterfaceSelfTestCtrlCommand	equ 0xAB
kbdReadOutputPortCtrlCommand	equ 0xD0
kbdWriteOutputPortCtrlCommand	equ 0xD1
kbdPulseCtrlCommand		equ 0xF0

kbdEnableCommand	equ 0xF4
kbdDisableCommand	equ 0xF5
kbdResetToDefaultCommand	equ 0xF6

kbdOutputPortA20	equ 0x02
kbdDataACK		equ 0xFA

	;; end of constants

	;;
	;; bootblock pseudo-location
	;; _MUST_ come last
	;; 
bootblock:	


