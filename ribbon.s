
	;;
	;; debugging ribbon
	;; Julian Squires <tek@wiw.org> / 2000
	;;

	;; change this if STRAP_CODELEN in strap.c is ever changed!
	;; (it should be 0x1000-STRAP_CODELEN)
	org 0x0c00

	;; 
	;; macros
	;; 

	;; io delay
%define ioDelay	out 0xED, ax
	;; old way:
	;;jmp short $+2
	;; new way: (as seen in Robert Collins' fu on x86.org)

	;; end of macros

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

	;; reset the disk drives
	;; commented out because it's SLOOOOOW and broken
	;call diskReset
	;call dot

	;; unmask IRQs
	call picReset
	call dot

	;; reset the timer
	;call pitReset
	;call dot

	;;
	;; keyboard:
	;;     reset keyboard
	;;     test keyboard
	;;     disable A20 gating
	;;
	call kbdReset
	call dot
	call kbdDisableA20
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

	;call resetWithBios

afterReset:
	sti

	;; make sure the ide controller is setup correctly
	mov dx, ideDeviceControlRegister
	mov al, ideDeviceControlMagic
	out dx, al
	ioDelay

; 	mov ax, 0x0201
; 	xor cx, cx
; 	xor bx, bx
; 	int 0x13
; 	call dot

	;; hack:
	;; windows mysteriously believes there is a drive IO error,
	;; asks you to replace the disk (htf one is supposed to do that
	;; to a hard drive, i don't know), and press any key.
	;; so we stuff the keyboard buffer with [enter] to make
	;; things move along a little quicker.

	mov ah, 0x05
	mov cx, 0x430D
	int 0x16

	;; tell the system to boot from the hard drive
	;; (dx = 0x0000 for floppy drive, 0x0080 for hard drive)
	;; change this if you'd like to boot a floppy instead.
	mov dx, 0x0080

	;; jump directly to bootblock
	jmp 0x0:0x7c00

	;; end of main function

	;; 
	;; helper procedures
	;;

	;; output . to screen
dot:	mov al, '.'
	call putc
	ret

	;;
	;; dumpdword
	;; output the dword passed in eax
	;; 
; dumpdword:
; 	push eax
; 	shr eax, 16
; 	call dumpword
; 	pop eax
; 	call dumpword
; 	ret

	;;
	;; dumpword
	;; output the word passed in ax
	;; 
; dumpword:
; 	push ax

; 	call dumpbyte
; 	mov ah, al
; 	call dumpbyte

; 	pop ax
; 	ret

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
	;; This is absolutely necessary, as Linux remaps the IRQ
	;; routing, and the BIOS can't deal with that.
	;; 
picReset:
	push ax

	cli
	;; ICW1
	mov al, 0x11
	out picMasterCommandRegister, al
	ioDelay
	out picSlaveCommandRegister, al
	ioDelay

	;; ICW2
	;; master starts at 0x08
	mov al, 0x08
	out picMasterMaskRegister, al
	ioDelay
	;; slave starts at 0x70
	mov al, 0x70
	out picSlaveMaskRegister, al
	ioDelay

	;; ICW3
	mov al, 0x04
	out picMasterMaskRegister, al
	ioDelay
	mov al, 0x02
	out picSlaveMaskRegister, al
	ioDelay

	;; ICW4
	mov al, 0x01
	out picMasterMaskRegister, al
	ioDelay
	out picSlaveMaskRegister, al
	ioDelay

	;; dump 8259 mask state
	;mov al, '<'
	;call putc
	;in al, picMasterMaskRegister
	;mov ah, al
	;call dumpbyte
	;mov al, '^'
	;call putc
	;in al, picSlaveMaskRegister
	;mov ah, al
	;call dumpbyte
	;mov al, '>'
	;call putc

	;; unmask all the IRQs just to be safe
	mov al, 0x0
	out picSlaveMaskRegister, al
	ioDelay
	out picMasterMaskRegister, al
	ioDelay

	;; send EOI (interrupt finished) to PIC, just in case Linux left an
	;; int ``with its pants down'', as it were
	mov al, picEndOfInterrupt
	out picMasterCommandRegister, al
	ioDelay
	out picSlaveCommandRegister, al
	ioDelay

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

	;;
	;; reset the 825[34] PIT (Programmable Interval Timer),
	;; 
; pitReset:
; 	push ax

; 	cli
; 	mov al, 0x36
; 	out 0x43, al
; 	ioDelay
; 	xor al, al
; 	out 0x40, al
; 	ioDelay
; 	out 0x40, al
; 	ioDelay
; 	sti

; 	pop ax
; 	ret

kbdResetInternal:
	;; reset keyboard
.l1:	mov al, kbdResetCommand
	out kbdDataRegister, al
	ioDelay
	;;   wait for ACK
	call kbdWaitForOutput
	in al, kbdDataRegister
	cmp al, kbdDataACK
	je .l3
	cmp al, kbdDataResend
	je .l1
	mov al, '?'
	call putc
.l3:	ret

kbdDisable:
	;; disable keyboard
.l1:	mov al, kbdDisableCommand
	out kbdDataRegister, al
	ioDelay
	;;   wait for ACK
	call kbdWaitForOutput
	in al, kbdDataRegister
	cmp al, kbdDataACK
	jne .l1
	ret

kbdEnable:
	;; enable keyboard
.l1:	mov al, kbdEnableCommand
	out kbdDataRegister, al
	ioDelay
	;;   wait for ACK
	call kbdWaitForOutput
	in al, kbdDataRegister
	cmp al, kbdDataACK
	jne .l1
	ret

	;;
	;; reset the 8042 as best we can
	;; 
kbdReset:
	push ax

	;; enable controller
	mov al, kbdEnableCtrlCommand
	out kbdControlRegister, al
	ioDelay

	call kbdResetInternal
	call kbdDisable
	;; write controller mode 65
	mov al, kbdWriteModeCtrlCommand
	out kbdControlRegister, al
	ioDelay
	;; magic mode
	mov al, 0x65
	out kbdDataRegister, al
	ioDelay

	call kbdEnable

	;; output controller mode
	mov al, kbdReadModeCtrlCommand
	out kbdControlRegister, al
	ioDelay
	call kbdWaitForOutput
	in al, kbdDataRegister
; 	mov ah, al
; 	call dumpbyte

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

	;; disable the A20 line
kbdDisableA20:
	push ax

	mov al, kbdReadOutputPortCtrlCommand
	out kbdControlRegister, al
	ioDelay
	in al, kbdDataRegister
	mov ah, al
	mov al, kbdWriteOutputPortCtrlCommand
	out kbdControlRegister, al
	ioDelay
	mov al, 0xDD		; FIXME
	out kbdDataRegister, al
	ioDelay

	pop ax
	ret

	;; perform self-tests
	;; note that this appears to royally mess up the keyboard
kbdTest:
	push ax

	;; keyboard self-test (as opposed to the keyboard interface)
	mov al, kbdSelfTestCtrlCommand
	out kbdControlRegister, al
	ioDelay
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
	ioDelay
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

	;;
ideWaitForBusyClear:
	push ax
	push dx

.l1:	mov dx, ideCommandRegister
	in al, dx
	test al, ideBusyStatus
	jnz .l1

	pop dx
	pop ax
	ret

	;;
ideWaitForDriveReady:
	push ax
	push dx

.l1:	mov dx, ideCommandRegister
	in al, dx
	test al, ideDriveReadyStatus
	jnz .l1

	pop dx
	pop ax
	ret

	;; reset floppy and hard drive systems via the bios
diskReset:
	xor ax, ax
	xor dx, dx

	;; reset the floppy disk system
	mov dl, 0x80
	int 0x13

	;; reset the first hard drive
	mov ah, 0x0D
	int 0x13
	ret

ideDumpStatus:
	push ax
	push dx

	call ideWaitForBusyClear
	mov dx, ideCommandRegister
	in al, dx
	mov ah, al
	call dumpbyte
	test al, ideErrorStatus
	jz .l1
	;; dump error register
	mov al, '!'
	call putc
	mov dx, ideErrorRegister
	in al, dx
	mov ah, al
	call dumpbyte
.l1:	
	pop dx
	pop ax
	ret

	;;
	;; use the bios to reset state
	;;
;resetWithBios:
	;; preserve memory
	; mov ax, biosSegment
; 	mov es, ax
; 	mov si, 0x0072
; 	;; tell the BIOS to preserve our memory (don't wipe)
; 	mov ax, 0x4321
; 	stosw
; 	mov si, 0x0067
; 	;; OLD
; 	;; jump back to 0000:7C00 when we finish (write 7c00 into 40:67)
; 	;;mov eax, bootLocation
; 	;; NEW
; 	;; jump ahead when we finish
; 	mov eax, afterReset
; 	stosd
; 	;; write into CMOS RAM that we want to go to [40:67]
; 	cli
; 	mov al, 0x0F
; 	or al, 0x80
; 	out cmosIndexRegister, al
; 	ioDelay
; 	;; change this to boot in different manners
;  	;; 0x04 will read floppy then hdd
; 	;; 0x05 will flush keyboard buffer, do an EOI, then jump to [40:67]
; 	;;                                  [End Of Interrupt, see pokepic]
; 	;; 0x0a will jump to our own code without the above
; 	mov al, 0x04
; 	out cmosDataRegister, al
; 	ioDelay
; 	mov al, 0x00
; 	out cmosIndexRegister, al
; 	ioDelay
; 	sti
; 	;; reset with the keyboard controller
; 	;; (slower than triple fault, but triple fault requires
; 	;;  modification of strap.c)
; 	;; note FE pulses bit 0 (cpu reset), because zero == pulse bit,
; 	;; while one == don't pulse.
; 	mov al, kbdPulseCtrlCommand | ~(0x1)
; 	out kbdControlRegister, al
; 	ioDelay

	;; we should never get here
	;; normal reset
; 	jmp 0xFFFF:0x0000
;	ret

	;; end of helper procedures

	;;
	;; data
	;;

oldInt9	resd 1

	;; end of data declarations

	;;
	;; constants
	;;

stackSegment		equ 0x0050 ; arbitrary
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

picEndOfInterrupt	equ 0x20 ; non-specific EOI

	;; keyboard related
kbdControlRegister	equ 0x64
kbdDataRegister		equ 0x60

kbdReadModeCtrlCommand	equ 0x20
kbdWriteModeCtrlCommand	equ 0x60
kbdSelfTestCtrlCommand		equ 0xAA
kbdInterfaceSelfTestCtrlCommand	equ 0xAB
kbdEnableCtrlCommand	equ 0xAE
kbdReadOutputPortCtrlCommand	equ 0xD0
kbdWriteOutputPortCtrlCommand	equ 0xD1
kbdPulseCtrlCommand		equ 0xF0

kbdEnableCommand	equ 0xF4
kbdDisableCommand	equ 0xF5
kbdResetCommand		equ 0xF6

kbdOutputPortA20	equ 0x02
kbdDataPOR		equ 0xAA
kbdDataACK		equ 0xFA
kbdDataResend		equ 0xFE

	;; ide related
ideErrorRegister	equ 0x01F1
ideCommandRegister	equ 0x01F7
ideDeviceControlRegister	equ 0x03F6

ideRecalibrateCommand	equ 0x10
ideReadCommand		equ 0x20
ideDiagnosticsCommand	equ 0x90

ideDeviceControlMagic	equ 0x0A ; nIEN and nothing else

ideBusyStatus		equ 0x80
ideDriveReadyStatus	equ 0x40
ideErrorStatus		equ 0x01

	;; end of constants

	;;
	;; bootblock pseudo-location
	;; _MUST_ come last
	;; 
bootblock:	
