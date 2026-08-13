/* segreg.S — mtsr, mfsr, mtsrin, mfsrin and tlbie.
 *
 * The segment registers are not in the state dump, so each one written is
 * read back into a GPR.  The indirect forms take the register number from
 * the top four bits of rB and ignore the rest, which is why r07 and r09
 * carry low bits that must not matter.
 *
 * tlbie is a no-op on this model (no TLB), so the only thing it can be
 * tested for is its privilege check — which is also what makes it the
 * cheapest way to exercise the supervisor guard the segment moves share.
 * That test is last, because reaching the handler halts.
 *
 * Expected: halt status 0x2A, SRR1 = 0x00045040, r04 = r05 = r10 =
 * 0x12345678, r06 = r08 = 0xABCDEF01, r07 = 0xD0001111, r09 = 0x3FFF0000,
 * r11 = 0 (SR0 still at its reset value), r12 = 0x5040, r14 = 0.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	lis	4, 0x1234
	ori	4, 4, 0x5678
	mtsr	3, 4			/* SR3 = 0x12345678 */
	mfsr	5, 3

	lis	6, 0xABCD
	ori	6, 6, 0xEF01
	lis	7, 0xD000
	ori	7, 7, 0x1111		/* SR number = 0xD; 0x1111 ignored */
	mtsrin	6, 7			/* SR13 = 0xABCDEF01 */
	mfsr	8, 13

	lis	9, 0x3FFF		/* SR number = 3 */
	mfsrin	10, 9

	tlbie	9			/* supervisor no-op */

	mfsr	11, 0			/* untouched segment register */

	/* --- the same instruction, in user mode ------------------------- */
	lis	3, 0xFFF0
	ori	3, 3, 0x0700		/* program exception vector */
	lis	12, 0x4400
	ori	12, 12, 0x0002		/* the sc instruction word */
	stw	12, 0(3)

	lis	0, 0x4600
	ori	0, 0, 0x0D1E		/* arm the halt magic */
	li	3, 0x2A			/* status that proves we got there */

	mfmsr	12
	ori	12, 12, 0x4000		/* MSR[PR] */
	mtmsr	12
	tlbie	9			/* -> privileged program exception */
	li	14, 0x99		/* must not execute */
	HALT(0)
