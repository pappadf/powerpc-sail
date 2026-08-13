/* fpconv.S — frsp, fctiw and fctiwz (MPC601UM Table 3-12).
 *
 * frsp is the identity operation delivered in single precision, so it is
 * where the single-format exponent range shows itself:
 *   1/3                rounds up into 0x3FD5555560000000, setting FR and FI
 *   2^-140             is a single DENORMAL and therefore tiny, but exactly
 *                      representable, so no underflow is signalled at all —
 *                      "tiny AND loss of accuracy" is the disabled rule
 *   3 * 2^-150         is tiny and inexact, an exact tie between one and two
 *                      single denormals, so it rounds to the even one
 *                      (0x36B0000000000000) with UX, XX, FR and FI
 *
 * fctiw rounds under FPSCR[RN] and fctiwz always toward zero, and the 601
 * fills the undefined high half of frD with x'FFF80000'.  An operand that
 * cannot be represented — here +infinity and a QNaN — is the invalid integer
 * convert condition, clamping high and low respectively.
 *
 * Expected (hex): r04=3FD55555 r05=60000000 r06=82064000
 *   r07=37300000 r08=0 r09=00004000 (nothing raised: tiny but exact)
 *   r11=36B00000 r12=0 r13=8A064000
 *   r14=00000002 r15=82020000 (2.5 -> 2, a tie rounded to even, FR clear)
 *   r16=00000004 r17=82060000 (3.5 -> 4, FR set)
 *   r18=00000002 r19=82020000 (fctiwz 2.9 -> 2)
 *   r20=7FFFFFFF r21=A0000100 (VXCVI)  r22=80000000 r23=A0000100
 *   r24=FFF80000 (the 601's high half).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	mfmsr	3
	ori	3, 3, 0x2000		/* MSR[FP]                           */
	mtmsr	3
	li	10, 0x4000
	li	3, 0

	/* --- constants ------------------------------------------------- */
	lis	4, 0x3FD5
	ori	4, 4, 0x5555
	lis	5, 0x5555
	ori	5, 5, 0x5555
	stw	4, 0(10)
	stw	5, 4(10)		/* 1/3                               */
	lis	4, 0x3730
	stw	4, 8(10)
	stw	3, 12(10)		/* 2^-140                            */
	lis	4, 0x36A8
	stw	4, 16(10)
	stw	3, 20(10)		/* 3 * 2^-150                        */
	lis	4, 0x4004
	stw	4, 24(10)
	stw	3, 28(10)		/* 2.5                               */
	lis	4, 0x400C
	stw	4, 32(10)
	stw	3, 36(10)		/* 3.5                               */
	lis	4, 0x4007
	ori	4, 4, 0x3333
	lis	5, 0x3333
	ori	5, 5, 0x3333
	stw	4, 40(10)
	stw	5, 44(10)		/* 2.9                               */
	lis	4, 0x7FF0
	stw	4, 48(10)
	stw	3, 52(10)		/* +infinity                         */
	lis	4, 0x7FF8
	stw	4, 56(10)
	stw	3, 60(10)		/* a quiet NaN                       */
	stw	3, 64(10)
	stw	3, 68(10)		/* 0.0, for clearing the FPSCR       */
	lfd	1, 0(10)
	lfd	2, 8(10)
	lfd	3, 16(10)
	lfd	4, 24(10)
	lfd	5, 32(10)
	lfd	6, 40(10)
	lfd	7, 48(10)
	lfd	8, 56(10)
	lfd	9, 64(10)

	/* --- frsp ------------------------------------------------------ */
	mtfsf	0xFF, 9
	frsp	10, 1
	stfd	10, 72(10)
	lwz	4, 72(10)
	lwz	5, 76(10)
	mffs	11
	stfd	11, 72(10)
	lwz	6, 76(10)

	mtfsf	0xFF, 9
	frsp	10, 2			/* tiny, but exact: no underflow     */
	stfd	10, 72(10)
	lwz	7, 72(10)
	lwz	8, 76(10)
	mffs	11
	stfd	11, 72(10)
	lwz	9, 76(10)

	mtfsf	0xFF, 9
	frsp	10, 3			/* tiny and inexact                  */
	stfd	10, 72(10)
	lwz	11, 72(10)
	lwz	12, 76(10)
	mffs	11
	stfd	11, 72(10)
	lwz	13, 76(10)

	/* --- fctiw / fctiwz -------------------------------------------- */
	mtfsf	0xFF, 9
	fctiw	10, 4			/* 2.5 -> 2 (tie to even)            */
	stfd	10, 72(10)
	lwz	24, 72(10)		/* the 601's x'FFF80000' high half   */
	lwz	14, 76(10)
	mffs	11
	stfd	11, 72(10)
	lwz	15, 76(10)

	mtfsf	0xFF, 9
	fctiw	10, 5			/* 3.5 -> 4                          */
	stfd	10, 72(10)
	lwz	16, 76(10)
	mffs	11
	stfd	11, 72(10)
	lwz	17, 76(10)

	mtfsf	0xFF, 9
	fctiwz	10, 6			/* 2.9 -> 2, toward zero             */
	stfd	10, 72(10)
	lwz	18, 76(10)
	mffs	11
	stfd	11, 72(10)
	lwz	19, 76(10)

	mtfsf	0xFF, 9
	fctiw	10, 7			/* +infinity: invalid, clamps high   */
	stfd	10, 72(10)
	lwz	20, 76(10)
	mffs	11
	stfd	11, 72(10)
	lwz	21, 76(10)

	mtfsf	0xFF, 9
	fctiw	10, 8			/* a NaN: invalid, clamps low        */
	stfd	10, 72(10)
	lwz	22, 76(10)
	mffs	11
	stfd	11, 72(10)
	lwz	23, 76(10)

	HALT(0)
