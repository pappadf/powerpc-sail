/* powerarith.S — the POWER arithmetic holdovers doz, dozi and nabs.
 *
 * These are 601-only (MPC601UM Table 3-2), so the assembler needs
 * `.machine "601"` before it will encode them.
 *
 * doz rD,rA,rB is a saturating subtract: rB - rA, or zero when rA is
 * algebraically greater than rB.  Only a POSITIVE overflow can set OV, which
 * the two dozo cases below pin from both sides.  nabs never overflows at all,
 * so nabso clears OV and leaves the sticky SO alone — while abs, its mirror,
 * overflows on exactly one input, the most negative number, which is its own
 * absolute value.
 *
 * Expected (hex): r04=5 r05=FFFFFFFB r06=FFFFFFF9 r07=FFFFFFF9 r08=80000000
 *   r09=80000000 r10=0 r11=A r12=4 r13=6 r14=0 r15=10 r16=0 r17=7FFFFFFF
 *   r18=FFFFFFFF r19=C0000000 r20=0 r21=0 r22=0 r23=5 r24=7
 *   r25=80000000 r26=C0000000,
 *   XER = C0000000 (SO|OV from the abso.), CR = 90000000 (CR0 = LT|SO, from
 *   the same instruction: the result is negative and SO is now set).
 */

#include "testlib.h"

	.text
	.machine "601"
	.globl _start
_start:
	/* --- nabs: rD = -|rA| ------------------------------------------ */
	li	4, 5
	nabs	5, 4			/* r5 = -5                          */
	li	6, -7
	nabs	7, 6			/* r7 = -7: already negative        */

	li	3, 0
	mtxer	3			/* clear XER incl. the sticky SO    */
	lis	8, 0x8000		/* r8 = 0x80000000                  */
	nabso.	9, 8			/* -|-2^31| = -2^31, and no overflow */
	mfxer	10			/* r10 = 0: OV cleared, SO untouched */

	/* --- doz / dozi ------------------------------------------------ */
	li	11, 10
	li	12, 4
	doz	13, 12, 11		/* 4 <= 10        -> 10 - 4 = 6     */
	doz	14, 11, 12		/* 10 > 4         -> 0              */
	dozi	15, 12, 20		/* 4 <= 20        -> 20 - 4 = 16    */
	dozi	16, 11, -5		/* 10 > -5        -> 0              */

	/* --- overflow is possible only where the difference is kept ---- */
	lis	17, 0x7FFF
	ori	17, 17, 0xFFFF		/* r17 = 0x7FFFFFFF                 */
	dozo	18, 8, 17		/* -2^31 <= 2^31-1: 2^32-1 overflows */
	mfxer	19			/* r19 = 0xC0000000 (SO|OV)         */
	mtxer	3
	dozo	20, 17, 8		/* 2^31-1 > -2^31 -> 0, no overflow */
	mfxer	21			/* r21 = 0                          */

	/* --- Rc=1 describes the value actually placed in rD ------------ */
	doz.	22, 11, 12		/* 0 -> CR0 = EQ                    */

	/* --- abs, the mirror of nabs and the one that CAN overflow ----- */
	abs	23, 4			/* |5| = 5                          */
	abs	24, 6			/* |-7| = 7                         */
	mtxer	3
	abso.	25, 8			/* |-2^31| is still -2^31: overflow */
	mfxer	26			/* r26 = 0xC0000000 (SO|OV)         */

	HALT(0)
