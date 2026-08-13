/* muldiv.S — integer multiply and divide.
 *
 * Covers mulli, the low/high-half multiplies (including a case where the
 * signed and unsigned high halves differ), mullwo overflow, truncate-toward-
 * zero signed division, and both undefined divisions (divide by zero and
 * 0x8000_0000 / -1), which must leave rD untouched while still setting OV.
 *
 * Expected (hex): r01=C0000000 r02=FFFFFFF2 r04=7 r05=FFFFFFEB r06=00010000
 *   r07=10000000 r08=00010002 r09=00030004 r10=000A0008 r11=3 r12=3
 *   r13=FFFFFFFE r14=3 r15=FFFFFFFF r16=2 r17=FFFFFFFA r18=40000000 r19=4
 *   r20=0 r21=C0000000 r22=64 r23=7 r24=E r25=E r26=FFFFFF9C r27=FFFFFFF2
 *   r28=80000000 r29=40000000 r30=C0000000 r31=000005A5,
 *   XER = C0000000 (SO|OV), CR = 90000000 (CR0 = LT|SO).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- mulli: low 32 bits, sign of the operands is irrelevant ----- */
	li	4, 7
	mulli	5, 4, -3		/* r5 = -21                         */
	lis	6, 0x0001		/* r6 = 0x00010000                  */
	mulli	7, 6, 0x1000		/* r7 = 0x10000000                  */

	/* --- mullw/mulhw/mulhwu: 0x00010002 * 0x00030004 --------------- */
	lis	8, 0x0001
	ori	8, 8, 0x0002		/* r8 = 0x00010002                  */
	lis	9, 0x0003
	ori	9, 9, 0x0004		/* r9 = 0x00030004                  */
	mullw	10, 8, 9		/* product = 0x0000_0003_000A_0008  */
	mulhw	11, 8, 9
	mulhwu	12, 8, 9

	/* --- where the signed and unsigned high halves differ ---------- */
	li	13, -2
	li	14, 3
	mulhw	15, 13, 14		/* -6        -> high = 0xFFFFFFFF   */
	mulhwu	16, 13, 14		/* 0x2FFFFFFFA -> high = 0x00000002 */
	mullw	17, 13, 14		/* low = 0xFFFFFFFA                 */

	/* --- mullwo: OV when the product does not fit in 32 bits -------- */
	li	3, 0
	mtxer	3			/* clear XER (incl. the sticky SO)  */
	lis	18, 0x4000		/* r18 = 0x40000000                 */
	li	19, 4
	mullwo	20, 18, 19		/* 0x1_00000000: r20 = 0, OV set    */
	mfxer	21			/* r21 = 0xC0000000 (SO|OV)         */

	/* --- divw/divwu: quotient truncates toward zero ---------------- */
	li	22, 100
	li	23, 7
	divw	24, 22, 23		/* 14                               */
	divwu	25, 22, 23		/* 14                               */
	li	26, -100
	divw	27, 26, 23		/* -14, not -15: truncate to zero   */
	lis	28, 0x8000		/* r28 = 0x80000000                 */
	li	2, 2
	divwu	29, 28, 2		/* 0x40000000                       */
	divw	30, 28, 2		/* -2^31 / 2 = 0xC0000000           */

	/* --- the two undefined divisions leave rD alone ----------------- */
	li	31, 0x5A5		/* marker: must survive both        */
	mtxer	3
	divwo	31, 22, 3		/* divide by zero: OV set only      */
	mfxer	1			/* r1 = 0xC0000000                  */
	mtxer	3
	li	2, -1
	divwo	31, 28, 2		/* 0x80000000 / -1: OV set only     */

	/* --- a recording divide fixes the final CR0 --------------------- */
	divw.	2, 26, 23		/* r2 = -14; CR0 = LT|SO            */

	HALT(0)
