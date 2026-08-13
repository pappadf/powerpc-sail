/* fpmadd.S — the multiply-add family (MPC601UM Table 3-11), whose point is
 * that the product is added to frB with NO intermediate rounding (§2.5.1.1).
 *
 * The operands are chosen so that the difference is total rather than a last
 * bit.  With a = 1 + 2^-52 and c = 1 - 2^-53, the exact product is
 * 1 + 2^-53 - 2^-105, and adding -1 leaves 2^-53 - 2^-105, which is
 * representable: fmadd delivers 0x3C9FFFFFFFFFFFFE.  Rounding the product
 * first, as the fmul/fadd pair below does, hits an exact tie at 1 + 2^-53,
 * rounds it to 1.0, and the addition then cancels to ZERO.
 *
 * fnmadd and fnmsub negate the rounded result; fmsub subtracts frB, so with
 * frB = -1 it produces the product plus one, which is exactly 2.0.
 * fmadds rounds the same exact intermediate to single precision, where the
 * 52 one-bits round up into 0x3CA0000000000000.
 *
 * Expected (hex): r04=3C9FFFFF r05=FFFFFFFE (fmadd)
 *   r06=0 r07=0 (the same arithmetic with a rounding in the middle)
 *   r08=BC9FFFFF r09=FFFFFFFE (fnmadd)  r11=40000000 r12=0 (fmsub)
 *   r13=C0000000 r14=0 (fnmsub)  r15=3CA00000 r16=0 (fmadds).
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

	/* --- a = 1 + 2^-52, b = -1.0, c = 1 - 2^-53 -------------------- */
	lis	4, 0x3FF0
	li	5, 1
	stw	4, 0(10)
	stw	5, 4(10)
	lis	4, 0xBFF0
	stw	4, 8(10)
	stw	3, 12(10)
	lis	4, 0x3FEF
	ori	4, 4, 0xFFFF
	li	5, -1
	stw	4, 16(10)
	stw	5, 20(10)
	lfd	1, 0(10)
	lfd	2, 8(10)
	lfd	3, 16(10)

	/* --- one rounding: the small difference survives ---------------- */
	fmadd	4, 1, 3, 2
	stfd	4, 24(10)
	lwz	4, 24(10)
	lwz	5, 28(10)

	/* --- two roundings: it does not ------------------------------- */
	fmul	5, 1, 3
	fadd	5, 5, 2
	stfd	5, 24(10)
	lwz	6, 24(10)
	lwz	7, 28(10)

	/* --- the negating and subtracting forms ----------------------- */
	fnmadd	6, 1, 3, 2
	stfd	6, 24(10)
	lwz	8, 24(10)
	lwz	9, 28(10)
	fmsub	7, 1, 3, 2
	stfd	7, 24(10)
	lwz	11, 24(10)
	lwz	12, 28(10)
	fnmsub	8, 1, 3, 2
	stfd	8, 24(10)
	lwz	13, 24(10)
	lwz	14, 28(10)

	/* --- and the same intermediate rounded to single precision ----- */
	fmadds	9, 1, 3, 2
	stfd	9, 24(10)
	lwz	15, 24(10)
	lwz	16, 28(10)

	HALT(0)
