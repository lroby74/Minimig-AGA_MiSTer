	section code,code
	dc.l	$00010000
	dc.l	start
start:
	lea	$8000,a0
	lea	$8100,a1
	lea	$9000,a2
	moveq	#7,d3
loop:
	movem.l	d0-d3/a0-a2,-(a7)
	move.l	(a0),d0
	add.l	d1,d0
	lsl.l	#2,d0
	move.l	d0,(a1)
	addi.l	#$1234,(a2)
	cmp.l	d1,d0
	bne.s	skip
	moveq	#0,d2
skip:
	tst.l	d0
	beq.s	other
	swap	d0
other:
	muls.w	d3,d2
	move.l	d2,d4
	and.l	#$FF,d4
	add.l	([$10,a0,d1.l],$20),d5
	movem.l	(a7)+,d0-d3/a0-a2
	divs.l	d3,d5
	moveq	#3,d6
inner:
	addq.l	#1,d5
	dbra	d6,inner
	bra.w	loop
