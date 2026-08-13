/* fpsingle.S — the single-precision arithmetic forms (MPC601UM Tables 3-10
 * and 3-11), and CR1.
 *
 * A single-precision instruction reads the same double operands and writes a
 * double result; what changes is that the intermediate is rounded to 24 bits
 * (§2.5.5).  Each case below is run in both precisions from the same inputs,
 * so the pairs differ only by that rounding:
 *
 *   1 + 2^-30      fadd  3FF0000000400000    fadds 3FF0000000000000
 *   1 - 2^-30      fsub  3FEFFFFFFF800000    fsubs 3FF0000000000000
 *   1/3 * 1/3      fmul  3FBC71C71C71C71C    fmuls 3FBC71C720000000
 *
 * 2^-30 is below half an ulp of 1.0 in single precision, so the first two
 * round back to exactly 1.0 while the double forms keep the bit.
 *
 * The three multiply-add s-forms follow, and then Rc=1: CR1 receives
 * FPSCR[FX FEX VX OX], not a comparison of the result, so `fadds.` after the
 * inexact operations above writes 1000 into CR1 — FX set, nothing else.
 * CR1 is the SECOND field, so that reads 0x08000000 in the whole register.
 *
 * Expected (hex): r04=3FF00000 r05=00400000 r06=3FF00000 r07=0
 *   r08=3FEFFFFF r09=FF800000 r11=3FF00000 r12=0
 *   r13=3FBC71C7 r14=1C71C71C r15=3FBC71C7 r16=20000000
 *   r17=3FF1C71C r18=80000000 (fmsubs)  r19=BFF1C71C r20=80000000 (fnmadds)
 *   r21=3FEC71C7 r22=20000000 (fnmsubs) r23=08000000 (CR after fadds.),
 *   CR = 08000000, XER = 0.
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

	/* --- 1.0, 2^-30, 1/3 (as a double), -1.0 ----------------------- */
	lis	4, 0x3FF0
	stw	4, 0(10)
	stw	3, 4(10)
	lis	4, 0x3E10
	stw	4, 8(10)
	stw	3, 12(10)
	lis	4, 0x3FD5
	ori	4, 4, 0x5555
	lis	5, 0x5555
	ori	5, 5, 0x5555
	stw	4, 16(10)
	stw	5, 20(10)
	lis	4, 0xBFF0
	stw	4, 24(10)
	stw	3, 28(10)
	lfd	1, 0(10)		/* 1.0                               */
	lfd	2, 8(10)		/* 2^-30                             */
	lfd	3, 16(10)		/* 1/3                               */
	lfd	4, 24(10)		/* -1.0                              */

	/* --- add: the double keeps the bit, the single does not -------- */
	fadd	5, 1, 2
	stfd	5, 32(10)
	lwz	4, 32(10)
	lwz	5, 36(10)
	fadds	5, 1, 2
	stfd	5, 32(10)
	lwz	6, 32(10)
	lwz	7, 36(10)

	/* --- subtract, the same pair ---------------------------------- */
	fsub	5, 1, 2
	stfd	5, 32(10)
	lwz	8, 32(10)
	lwz	9, 36(10)
	fsubs	5, 1, 2
	stfd	5, 32(10)
	lwz	11, 32(10)
	lwz	12, 36(10)

	/* --- multiply: a mantissa that shows the truncation ------------ */
	fmul	5, 3, 3
	stfd	5, 32(10)
	lwz	13, 32(10)
	lwz	14, 36(10)
	fmuls	5, 3, 3
	stfd	5, 32(10)
	lwz	15, 32(10)
	lwz	16, 36(10)

	/* --- the multiply-add s-forms, all over 1/3 * 1/3 -+ 1.0 ------- */
	fmsubs	5, 3, 3, 4		/* (1/3)^2 - (-1) = +1.0111...       */
	stfd	5, 32(10)
	lwz	17, 32(10)
	lwz	18, 36(10)
	fnmadds	5, 3, 3, 1		/* -((1/3)^2 + 1)                    */
	stfd	5, 32(10)
	lwz	19, 32(10)
	lwz	20, 36(10)
	fnmsubs	5, 3, 3, 1		/* -((1/3)^2 - 1)                    */
	stfd	5, 32(10)
	lwz	21, 32(10)
	lwz	22, 36(10)

	/* --- Rc=1 copies the FPSCR summary bits into CR1 --------------- */
	fadds.	5, 1, 2
	mfcr	23

	HALT(0)
