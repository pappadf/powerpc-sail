/* fpexc.S — the floating-point exception conditions of §5.4.7 and the
 * results they deliver, which differ between the enabled and disabled cases.
 *
 * Each case clears the FPSCR with `mtfsf 0xFF,f5` (f5 is 0.0, so its low word
 * is zero), performs one operation, and records the result and the FPSCR.
 * The cases, in order:
 *
 *  a  overflow, disabled, round to nearest    -> +infinity, OX, XX and FI:
 *     the delivered result is not the value the operation produced, so it
 *     is inexact by construction (Tables 2-1/5-17 bit 14)
 *  b  overflow, disabled, round toward zero   -> the largest finite double
 *  c  overflow, ENABLED                       -> the rounded result with its
 *     exponent lowered by 1536 (§5.4.7.4.1), so the handler sees a number:
 *     2 * maxdouble is exactly 0x1FFFFFFFFFFFFF * 2^972, and scaling gives
 *     0x1FFFFFFFFFFFFFFF
 *  d  underflow, disabled                     -> the smallest denormal times
 *     0.5 is an exact tie at half of it, so it rounds to +0 with UX and XX,
 *     and with FI: §5.4.7.5.1 does not clear FR/FI the way the invalid,
 *     zero-divide and disabled-overflow cases do, so §2.5.6's general
 *     "rounding occurred" rule stands
 *  e  zero divide                             -> +infinity, ZX
 *  f  0/0                                     -> VXZDZ, and the generated
 *     QNaN 0x7FF8000000000000
 *  g  infinity - infinity with VE SET         -> suppressed: frD keeps the
 *     42.0 put there beforehand, and FPRF is left alone too
 *
 * Expected (hex): r04=7FF00000 r05=92025000 r06=7FEFFFFF r07=92024001
 *   r08=1FFFFFFF r09=FFFFFFFF r11=D0004040 r12=0 r13=0 r14=8A022000
 *   r15=7FF00000 r16=0 r17=84005000 r18=7FF80000 r19=0 r20=A0211000
 *   r21=40450000 r22=0 r23=E0800080.
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

	/* --- 1.0, the largest finite double, 0.5, the smallest denormal,
	 *     0.0, +infinity and a 42.0 marker ------------------------- */
	lis	4, 0x3FF0
	stw	4, 0(10)
	stw	3, 4(10)
	lis	4, 0x7FEF
	ori	4, 4, 0xFFFF
	stw	4, 8(10)
	li	5, -1
	stw	5, 12(10)
	lis	4, 0x3FE0
	stw	4, 16(10)
	stw	3, 20(10)
	stw	3, 24(10)
	li	5, 1
	stw	5, 28(10)
	stw	3, 32(10)
	stw	3, 36(10)
	lis	4, 0x7FF0
	stw	4, 40(10)
	stw	3, 44(10)
	lis	4, 0x4045
	stw	4, 48(10)
	stw	3, 52(10)
	lfd	1, 0(10)		/* 1.0                               */
	lfd	2, 8(10)		/* 1.7976931348623157e308            */
	lfd	3, 16(10)		/* 0.5                               */
	lfd	4, 24(10)		/* 4.9406564584124654e-324           */
	lfd	5, 32(10)		/* 0.0                               */
	lfd	6, 40(10)		/* +infinity                         */
	lfd	7, 48(10)		/* 42.0                              */

	/* --- a: overflow, round to nearest ----------------------------- */
	mtfsf	0xFF, 5
	fadd	8, 2, 2
	stfd	8, 56(10)
	lwz	4, 56(10)
	mffs	10
	stfd	10, 56(10)
	lwz	5, 60(10)

	/* --- b: the same overflow rounding toward zero ----------------- */
	mtfsf	0xFF, 5
	mtfsfi	7, 1			/* RN = toward zero                  */
	fadd	8, 2, 2
	stfd	8, 56(10)
	lwz	6, 56(10)
	mffs	10
	stfd	10, 56(10)
	lwz	7, 60(10)

	/* --- c: overflow with OE set delivers a scaled number ---------- */
	mtfsf	0xFF, 5
	mtfsb1	25			/* OE                                */
	fadd	8, 2, 2
	stfd	8, 56(10)
	lwz	8, 56(10)
	lwz	9, 60(10)
	mffs	10
	stfd	10, 56(10)
	lwz	11, 60(10)

	/* --- d: underflow -------------------------------------------- */
	mtfsf	0xFF, 5
	fmul	8, 4, 3
	stfd	8, 56(10)
	lwz	12, 56(10)
	lwz	13, 60(10)
	mffs	10
	stfd	10, 56(10)
	lwz	14, 60(10)

	/* --- e: zero divide ------------------------------------------ */
	mtfsf	0xFF, 5
	fdiv	8, 1, 5
	stfd	8, 56(10)
	lwz	15, 56(10)
	lwz	16, 60(10)
	mffs	10
	stfd	10, 56(10)
	lwz	17, 60(10)

	/* --- f: 0/0 is an invalid operation, not a zero divide -------- */
	mtfsf	0xFF, 5
	fdiv	8, 5, 5
	stfd	8, 56(10)
	lwz	18, 56(10)
	lwz	19, 60(10)
	mffs	10
	stfd	10, 56(10)
	lwz	20, 60(10)

	/* --- g: an ENABLED invalid operation writes nothing ----------- */
	mtfsf	0xFF, 5
	mtfsb1	24			/* VE                                */
	fmr	8, 7			/* put 42.0 where the result would go */
	fsub	8, 6, 6			/* infinity - infinity: suppressed   */
	stfd	8, 56(10)
	lwz	21, 56(10)
	lwz	22, 60(10)
	mffs	10
	stfd	10, 56(10)
	lwz	23, 60(10)

	HALT(0)
