SIGNATURE		equ	0x4B4F4941
SAVE_EXT_START	equ	0x73D4
SAVE_SIZE		equ	0x8000

LOAD_ADDR		equ	0x202A000
UNC_ADDR		equ	0x202B000

.gba
.create CARD_FILE,0x0
.area 0x5C,0x00

@@header:
	.dh	@@scr0 - @@header

@@scr0:
	// Script handler exploit
//.if @@hook & 1
//	.db	0xF8,0x01,0x00,0x20
//	.db	0xF8,0x01,0x01,0x1D
//.else
	.db	0xF8,0x01,0x00,0xE0
	.db	0xF8,0x01,0x01,0x1C
//.endif
	.db	0xF8,0x01,0x02,0x00
	.db	0xF8,0x01,0x03,0x47
@@hook:
	.db	0xFF,0x35

.align 2
@@asm:
	// Set up a ROP call to ED FF
	// This way we can re-run this function next frame
	ldr	r0,[r2,0x20]
	add	r0,0x54
	push	r0,r14
	// r0    = call ED FF
	// r14   = return after ED FF

	// Check data present
	ldr	r1,=(0xE000000 + SAVE_EXT_START)
	ldrb	r0,[r1]
	cmp	r0,0x10
	bne	LoadEnd

	// Check data loaded
	ldr	r1,=UNC_ADDR
	ldr	r0,[r1,(HeaderSignature - Header)]
	ldr	r1,=SIGNATURE
	cmp	r0,r1
	beq	RunExt

Load:
	// Copy to RAM
	ldr	r0,=LOAD_ADDR
	ldr	r1,=(0xE000000 + SAVE_EXT_START)
	ldr	r2,=(SAVE_SIZE - SAVE_EXT_START)
@@copy:
	sub	r2,0x1
	ldrb	r3,[r1,r2]
	strb	r3,[r0,r2]
	bne	@@copy

	// LZ uncompress
//	ldr	r0,=LOAD_ADDR
	ldr	r1,=UNC_ADDR
	swi	0x11

RunExt:
	ldr	r0,=UNC_ADDR
	add	r1,r0,(Entry - Header + 1)
	mov	r14,r15
	bx	r1
Return:

LoadEnd:
	pop	r15

	.pool

.endarea
.close


.gba
.create SAVE_EXT_FILE,0

Header:
HeaderSignature:
	.dw	SIGNATURE
Entry:
	b	Start
ChecksumOffset:
	.dh	Checksum - Header

.align 4
Vars:
.align 1
.definelabel	VAR_CARD_IDX,	(. - Header)
	.db	0xFF
.definelabel	VAR_WAIT_COUNT,	(. - Header)
	.db	0x00
.align 4
.definelabel	VAR_CURSOR_POS,	(. - Header)
	.dw	0x000000F0		// 0xF0 = not drawn

.align 4
Checksum:
	.dw	0x0

.align 2
Start:
	// Passed in:
	// r0 = Header

	// First we need to check if the game is in a state where it's safe for us to
	// print description text
@@checkIdle:
	// Only run if menu is not scrolling, otherwise the game will lag
	mov	r1,r10
	ldr	r1,[r1,0x34]
	ldrb	r2,[r1,0x2]	// state
	ldrb	r1,[r1,0xC]	// scroll

	cmp	r1,0xC0
	bne	@@notIdle

	// If fading out, run for 1 frame otherwise the text box stays empty
	cmp	r2,0x08	// fading out
	bne	@@calcChecksum

	// check if we are on first frame of fade out
	ldr	r2,=0x200A7A0
	ldrb	r2,[r2,0x6]		// this is SUPER HACKY
	cmp	r2,0x10
	beq	@@calcChecksum
//	b	@@notIdle

@@notIdle:
	mov	r0,0x0
	mov	r15,r14

	// Next we need to check if all our data is still intact
	// Other parts of the game may also use this buffer...
	// This has to be one of the first things we do before doing anything else,
	// though we had to check for scrolling above to avoid game lag.
	// If we got here that means the signature is still intact, we'll have to
	// assume that this code is also still intact... (up until LoadOK)
@@calcChecksum:
	push	r0

	// Check if we need to reload
	// We can't capture a reload event so this is a heuristic...
	add	r0,(Start - Header)	// = Start
	ldr	r1,=(End - Start - 1)
	mov	r2,0x0
@@checksumLoop:
	ldrb	r3,[r0,r1]
	add	r2,r2,r3
	sub	r1,0x1
	bpl	@@checksumLoop

@@checksumVerify:
	pop	r0

	ldr	r1,[r0,(Checksum - Header)]
	cmp	r1,r2
	beq	LoadOK

	// Force a reload
	mov	r0,r14
	sub	r0,(Return - Load)
	mov	r15,r0

	.pool

LoadOK:
	// r0 = Header
	push	r6-r7,r14
	mov	r7,r0			// = Header

@@getCardIdx:
	// Get current card index
	mov	r0,r10
	ldr	r0,[r0,0x34]
	ldrh	r2,[r0,0x3C]	// selected index

@@getCardID:
	// Get pointer to current card ID
	mov	r0,r10
	ldr	r6,[r0,0x70]
	add	r6,r6,r2		// address of card ID
	ldrb	r0,[r6]		// card ID
	cmp	r0,0xFF
	bne	@@checkWaitCount
	add	r6,0x7

@@checkWaitCount:
	// On the first frame this text is called after a reload,
	// OAM 0 will not have been drawn yet
	ldr	r3,=0x3002E50
	ldr	r3,[r3]		// OAM 0 attributes
	cmp	r3,0x000000F0	// not set

	// To avoid redrawing twice in a row
	ldrb	r0,[r7,VAR_WAIT_COUNT]
	cmp	r0,0x0
	beq	@@checkFirstCall

	sub	r0,0x1
	strb	r0,[r7,VAR_WAIT_COUNT]
	strb	r2,[r7,VAR_CARD_IDX]
	str	r3,[r7,VAR_CURSOR_POS]

	b	@@checkButton

@@checkFirstCall:
	// Render card text first call
	ldrb	r0,[r7,VAR_CARD_IDX]
	ldr	r1,[r7,VAR_CURSOR_POS]
	strb	r2,[r7,VAR_CARD_IDX]
	str	r3,[r7,VAR_CURSOR_POS]
	cmp	r0,r2
	bne	@@redraw
	cmp	r1,r3
	beq	@@checkButton

@@redraw:
	mov	r0,0x1
	strb	r0,[r7,VAR_WAIT_COUNT]
	b	@@startText

@@checkButton:
	ldrb	r0,[r6]		// card ID

	mov	r1,r10
	ldr	r1,[r1,0x4]
	ldrh	r1,[r1,0x4]
@@checkR:
	lsr	r2,r1,0x9
	bcc	@@checkL

	// Go to next card
//	add	r0,(1)
	mov	r1,0x1
	bl	NextCard

@@checkL:
	lsr	r2,r1,0xA
	bcc	@@checkMinMax

	// Go to prev card
//	sub	r0,(1)
	mov	r1,0x0
	mvn	r1,r1
	bl	NextCard

@@checkMinMax:
//@@checkMin:
//	cmp	r0,(1)
//	bge	@@checkMax
//	mov	r0,(133)
//@@checkMax:
//	cmp	r0,(133)
//	ble	@@setID
//	mov	r0,(1)

@@setID:
	// r0 = new card ID
	ldrb	r1,[r6]		// old card ID
	cmp	r0,r1
	beq	@@end
	strb	r0,[r6]		// card ID

	// Play SFX
	mov	r0,0x66
.if TARGET == "en"
	ldr	r1,=0x8000558|1	// for EU
	ldr	r2,=0x80000AE
	ldrb	r2,[r2,0x1]		// region byte
	cmp	r2,0x50		// EU
	beq	@@doPlaySFX
	add	r1,(0x8000560 - 0x8000558)
.elseif TARGET == "jp"
	ldr	r1,=0x8000558|1
.else
	.error "Unknown target "+TARGET
.endif
@@doPlaySFX:
	mov	r14,r15
	bx	r1

@@startText:
	ldrb	r0,[r6]		// card ID
	add	r1,=CardNames
	lsl	r0,r0,0x1
	ldrh	r0,[r1,r0]		// script offset
	add	r0,r1,r0		// script pointer


	// Set script pointer to buffer, and copy script there
	push	r4
	ldr	r4,=(TextBuffer - Header)
	add	r4,r7,r4
	mov	r1,r4
@@copyScript:
	ldrb	r2,[r0]
	cmp	r2,0xE5
	beq	@@writeScriptEnd
	strb	r2,[r1]
	add	r0,0x1
	add	r1,0x1
	b	@@copyScript

@@writeScriptEnd:
	// Align to width of 4
	lsl	r2,r1,0x1E
	beq	@@writeReturnHook
	mov	r2,0x0
	strb	r2,[r1]
	add	r1,0x1
	b	@@writeScriptEnd

@@writeReturnHook:
	// Write the ACE trigger again
	mov	r2,0x0
	strb	r2,[r1]
	strb	r2,[r1,0x1]
	mov	r2,0xFF
	strb	r2,[r1,0x2]
	mov	r2,0x35
	strb	r2,[r1,0x3]
	add	r1,0x4

	add	r0,=ScriptEndHook
	ldr	r2,=(ScriptEndHookPtr - ScriptEndHook)
@@writeScriptEndHookLoop:
	ldmia	[r0]!,r3
	stmia	[r1]!,r3
	sub	r2,0x4
	bne	@@writeScriptEndHookLoop
	pop	r0			// current (previous) script pointer
	str	r0,[r1]

	str	r4,[r5,0x2C]	// script pointer for parsing
	str	r4,[r5,0x34]	// script pointer for display
	mov	r0,0x1
	pop	r6-r7,r15

@@end:
	mov	r0,0x0
	pop	r6-r7,r15

NextCard:
	// r0 = card ID
	// r1 = 1: next, -1: prev
	// r7 = Header
	// returns r0 = new card ID
	push	r4-r6,r14

	// Get current card index
	mov	r2,r10
	ldr	r2,[r2,0x34]
	ldrh	r2,[r2,0x3C]	// selected index

	add	r3,=Addresses
	lsl	r2,r2,0x2
	add	r2,r3,r2
	ldr	r3,[r2,0x4]		// r3 = end address
	ldr	r2,[r2]		// r2 = start address
	sub	r3,r3,r2		// count

	cmp	r1,0x0
	bgt	@@start
@@setupPrev:
	add	r2,r2,r3		// start + count
	sub	r2,0x1		// start + count - 1

@@start:
	ldrb	r4,[r7,r2]		// wrap card ID
@@loop:
	// r0 = card ID
	// r1 = 1: next, -1: prev
	// r2 = current address
	// r3 = count
	// r4 = wrap card ID

	// next: first card > id, else wrap
	// prev: first card < id, else wrap
	ldrb	r5,[r7,r2]
	cmp	r1,0x0
	bgt	@@checkNext
@@checkPrev:
	cmp	r5,r0
	blt	@@found
	b	@@next
@@checkNext:
	cmp	r5,r0
	bgt	@@found
//	b	@@next
@@next:
	add	r2,r2,r1
	sub	r3,0x1
	bne	@@loop

@@wrap:
	mov	r0,r4

	// Get game version
	ldr	r6,=0x80000AE
	ldrb	r6,[r6]	// 0x57 = Red Sun, 0x42 = Blue Moon

	// Quick fix for Red Sun wrapping around to WoodSoul
	cmp	r0,(132)	// #132 WoodSoul
	bne	@@end
	cmp	r6,0x57
	bne	@@end
	mov	r0,(126)	// #126 ThunderSoul

	b	@@end

@@found:
	// Get game version
	ldr	r6,=0x80000AE
	ldrb	r6,[r6]	// 0x57 = Red Sun, 0x42 = Blue Moon

	cmp	r5,(133)	// #000 Buster MiniBomb
	bge	@@ok
	cmp	r5,(127)	// #127 ProtoSoul
	bge	@@blueMoon
	cmp	r5,(121)	// #121 RollSoul
	blt	@@ok
@@redSun:
	cmp	r6,0x57
	bne	@@next
	b	@@ok
@@blueMoon:
	cmp	r6,0x42
	bne	@@next
//	b	@@ok

@@ok:
	mov	r0,r5
//	b	@@end

@@end:
	pop	r4-r6,r15

	.pool

// This function is copied at the end of the card description text.
// Its purpose is to return to the original card description script.
// This is needed because we can't do any of the following:
//  *  Call the description script like a variable print;
//      -> The menu handler doesn't expect this and will hang in the text
//         handler if you exit or switch pages while it's still printing the
//         description text.
//  *  Jump back to script 0 (with any script command that can jump);
//      -> This causes the text box to be cleared.
// So instead we trigger ACE again at the end of the descrription script and use
// this small function to fix our script pointer again.
.align 4
ScriptEndHook:
	ldr	r4,[ScriptEndHookPtr]
	str	r4,[r5,0x2C]	// script pointer for parsing
	str	r4,[r5,0x34]	// script pointer for display
	mov	r15,r14
.align 4
ScriptEndHookPtr:
	.dw	0x0

.align 4
Addresses:
	.dw	(Address0A - Header)
	.dw	(Address0B - Header)
	.dw	(Address0C - Header)
	.dw	(Address0D - Header)
	.dw	(Address0E - Header)
	.dw	(Address0F - Header)
	.dw	(AddressEnd - Header)

.align 4
CardNames:
	.import TEXT_FILE

Address0A:
	// 000 = 133 internally
	.db	(001), (004), (005), (008), (009), (012), (013), (017), (019), (033), (038), (043), (044), (047), (048), (049), (064), (067), (092), (094), (096), (102), (106), (107), (108), (111), (133)
Address0B:
	.db	(003), (006), (010), (031), (034), (035), (050), (061), (066), (074), (091), (093), (095), (097), (099), (100)
Address0C:
	.db	(002), (007), (011), (032), (036), (045), (046), (059), (060), (063), (075), (076), (078), (089), (090), (109)
Address0D:
	.db	(014), (015), (016), (018), (039), (040), (041), (042), (062), (068), (069), (070), (071), (072), (073), (077), (103), (105), (110), (112)
Address0E:
	.db	(020), (021), (022), (023), (024), (025), (026), (027), (037), (051), (052), (053), (054), (055), (056), (057), (058), (065), (079), (080), (081), (082), (083), (084), (085), (086), (087), (098), (101), (104), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128), (129), (130), (131), (132)
Address0F:
	.db	(028), (029), (030), (088)
AddressEnd:

End:

TextBuffer:

.close
