/* fparith.S — floating-point add, subtract, multiply and divide
 * (MPC601UM Table 3-10), in both precisions.
 *
 * Every result is stored with stfd and read back word by word, so the
 * expectations below are exact bit patterns rather than approximations.
 * They were computed independently (IEEE 754 round-to-nearest-even) and not
 * read off this model:
 *
 *   1/3 double        3FD5555555555555     1/3 single        3FD5555560000000
 *   1/3 + 1/3         3FE5555555555555     1 - 1/3           3FE5555555555556
 *   (1/3) * 3         3FF0000000000000  (exact, despite 1/3 not being)
 *
 * The last pair is the point of the test: 2/3 computed two ways differs in
 * the last bit, which only a correctly rounded implementation reproduces.
 * The two additions at the end pin the tie-breaking rule — 1 + 2^-53 is
 * exactly halfway between 1.0 and the next double up, so it rounds to even
 * and stays 1.0 while setting XX and FI but NOT FR, whereas 1 + 2^-52 is
 * representable and sets nothing at all.
 *
 * Expected (hex): r04=3FD55555 r05=55555555 r06=3FD55555 r07=60000000
 *   r08=3FE55555 r09=55555555 r11=3FE55555 r12=55555556 r13=3FF00000 r14=0
 *   r15=3FF00000 r16=0 r17=82024000 (FX|XX|FI|FPRF=+normal)
 *   r18=3FF00000 r19=00000001 r20=00004000 (FPRF alone: nothing was raised).
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

	/* --- constants: 1.0, 3.0, 2^-53, 2^-52 ------------------------- */
	lis	4, 0x3FF0
	stw	4, 0(10)
	stw	3, 4(10)
	lis	4, 0x4008
	stw	4, 8(10)
	stw	3, 12(10)
	lis	4, 0x3CA0
	stw	4, 16(10)
	stw	3, 20(10)
	lis	4, 0x3CB0
	stw	4, 24(10)
	stw	3, 28(10)
	lfd	1, 0(10)
	lfd	2, 8(10)
	lfd	3, 16(10)
	lfd	4, 24(10)

	/* --- divide, in both precisions -------------------------------- */
	fdiv	5, 1, 2
	stfd	5, 32(10)
	lwz	4, 32(10)
	lwz	5, 36(10)
	fdivs	6, 1, 2
	stfd	6, 32(10)
	lwz	6, 32(10)
	lwz	7, 36(10)

	/* --- 2/3 computed two ways, differing in the last bit ---------- */
	fadd	7, 5, 5
	stfd	7, 32(10)
	lwz	8, 32(10)
	lwz	9, 36(10)
	fsub	8, 1, 5
	stfd	8, 32(10)
	lwz	11, 32(10)
	lwz	12, 36(10)

	/* --- and a product that comes out exact ------------------------ */
	fmul	9, 5, 2
	stfd	9, 32(10)
	lwz	13, 32(10)
	lwz	14, 36(10)

	/* --- rounding: an exact tie goes to even ----------------------- */
	mtfsf	0xFF, 1			/* f1's low word is zero: FPSCR <- 0 */
	fadd	10, 1, 3		/* 1 + 2^-53                         */
	stfd	10, 32(10)
	lwz	15, 32(10)
	lwz	16, 36(10)
	mffs	11
	stfd	11, 32(10)
	lwz	17, 36(10)		/* inexact, but not incremented      */

	/* --- while the next size up is exact and raises nothing -------- */
	mtfsf	0xFF, 1
	fadd	10, 1, 4		/* 1 + 2^-52                         */
	stfd	10, 32(10)
	lwz	18, 32(10)
	lwz	19, 36(10)
	mffs	11
	stfd	11, 32(10)
	lwz	20, 36(10)

	HALT(0)
