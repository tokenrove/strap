
mode_switch:
	o32 mov eax, cr0
	;; turn off everything but PE (protection) and a reserved bit
	o32 and eax, 0x00000011
	;; turn on CD (cache disable) and NW (not write-through)
	o32 or eax,  0x60000000
	o32 mov cr0, eax
	o32 xor ebx, ebx
	o32 mov cr3, ebx
	o32 mov ebx, cr0
	o32 and ebx, 0x60000000
	jz .l1
	invd
	;; turn off PE
.l1:	and al, 0x10
	o32 mov cr0, eax
	;; absolute far jump to purge prefetch cache
	db 0xea
	;; note that this magic is programmatically generated in strap.c
	db 0x00
	db 0x0c
	db 0x00
	db 0x00
