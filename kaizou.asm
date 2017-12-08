CARD_NO equ 0
ENGLISH equ 1
REVISION equ 0

.gba
.create "card.msg",0x0
.area 0x5C

@@header:
	.dh	@@scr0 - @@header

@@scr0:
	// Print current number
	.db	0xF1
	.db	0xF0,0x00,0x00
	.db	0xF9,0x03,0xC3,0x01

	// Script handler exploit
	.db	0xF8,0x01,0x00,0xE0
	.db	0xF8,0x01,0x01,0x1C
	.db	0xF8,0x01,0x02,0x00
	.db	0xF8,0x01,0x03,0x47
	.db	0xFF,0x35

.align 2
@@asm:
	// Set up a ROP call to ED FF
	ldr	r0,[r2,20h]
	add	r0,54h
	push	r0,r14
	// r14   = return after ED FF
	// r0    = call ED FF

	// Get current card num
	mov	r2,r10
	ldr	r2,[r2,70h]
	ldrb	r0,[r2,CARD_NO]
	cmp	r0,0FFh
	bne	@@checkSelect

	add	r2,7h
	ldrb	r0,[r2,CARD_NO]

@@checkSelect:
	// Check Select pressed
	ldrh	r1,[r5,24h]
	lsr	r1,r1,3h
	bcc	@@check000

	// Increment card num
	add	r0,1h
	cmp	r0,85h
	ble	@@store
	sub	r0,85h
@@store:
	strb	r0,[r2,CARD_NO]

@@check000:
	cmp	r0,85h
	bne	@@update
	mov	r0,0h

@@update:
	ldr	r1,[r5,4Ch]
	str	r0,[r5,4Ch]
	cmp	r0,r1
	beq	@@end
	sub	r4,18h
	str	r4,[r5,34h]

@@end:
	// call sub_6510 then ED FF via ROP
	push	r1-r7
.if ENGLISH == 0
	ldr	r1,=8006511h+2h
.elseif REVISION == 1
	ldr	r1,=80064F1h+2h
.else
	ldr	r1,=80064EDh+2h
.endif
	bx	r1

	.pool

.notice 0x5C-.

.endarea
.close