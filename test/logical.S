/* logical.S — the integer logical instructions, sign extension and
 * count-leading-zeros.
 *
 * The two X-form sources are r4 = 0xF0F0AAAA and r5 = 0x0FF0CCCC, chosen so
 * that every one of the eight X-form results is distinct.  The final
 * instruction is a recording form with a negative result and XER[SO] set, so
 * the dumped CR checks both the LT bit and the SO copy.
 *
 * Expected (hex): r04=F0F0AAAA r05=0FF0CCCC r06=00F08888 r07=FFF0EEEE
 *   r08=FF006666 r09=FF0F7777 r10=000F1111 r11=00FF9999 r12=F0002222
 *   r13=F0FFBBBB r14=F0F0AAAF r15=F0FFAAAA r16=F0F05555 r17=0F0FAAAA
 *   r18=000000AA r19=00F00000 r20=000000FF r21=FFFFFFFF r22=12348000
 *   r23=FFFF8000 r24=0 r25=1 r26=1F r27=0 r28=20 r29=80000000 r30=0
 *   r31=F0FFBBBB, XER = 80000000, CR = 90000000 (CR0 = LT|SO).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	lis	4, 0xF0F0
	ori	4, 4, 0xAAAA		/* r4 = 0xF0F0AAAA                */
	lis	5, 0x0FF0
	ori	5, 5, 0xCCCC		/* r5 = 0x0FF0CCCC                */

	/* --- the eight X-form logicals ---------------------------------- */
	and	6, 4, 5
	or	7, 4, 5
	xor	8, 4, 5
	nand	9, 4, 5
	nor	10, 4, 5
	eqv	11, 4, 5
	andc	12, 4, 5		/* r4 & ~r5                       */
	orc	13, 4, 5		/* r4 | ~r5                       */

	/* --- the D-form logicals (note: rA is the destination) ---------- */
	ori	14, 4, 0x000F
	oris	15, 4, 0x000F
	xori	16, 4, 0xFFFF
	xoris	17, 4, 0xFFFF
	andi.	18, 4, 0x00FF		/* no Rc bit: CR0 always updated  */
	andis.	19, 4, 0x00FF

	/* --- sign extension -------------------------------------------- */
	li	20, 0xFF
	extsb	21, 20			/* 0x000000FF -> 0xFFFFFFFF       */
	lis	22, 0x1234
	ori	22, 22, 0x8000		/* r22 = 0x12348000               */
	extsh	23, 22			/* -> 0xFFFF8000                  */
	extsb	24, 22			/* low byte is zero -> 0          */

	/* --- count leading zeros, including both end cases -------------- */
	li	25, 1
	cntlzw	26, 25			/* 31                             */
	li	27, 0
	cntlzw	28, 27			/* 32                             */
	lis	29, 0x8000
	cntlzw	30, 29			/* 0                              */

	/* --- CR0 from a recording form, with XER[SO] set ---------------- */
	lis	3, 0x8000
	mtxer	3			/* XER[SO] = 1                    */
	orc.	31, 4, 5		/* negative result -> CR0 = LT|SO */

	HALT(0)
