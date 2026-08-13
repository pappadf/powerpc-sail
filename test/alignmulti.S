/* alignmulti.S — the up-front range check on a multiple-word transfer.
 *
 * §5.4.6.1: for a string or multiple the whole transfer is checked before
 * the instruction begins, so when it faults "it is guaranteed that no
 * portion of the instruction has been executed".  Here a word-aligned lmw
 * of twelve registers starts four bytes below 0x1000_0000 and so spans a
 * 256 MB boundary, which always faults regardless of alignment.  The
 * markers in r20..r23 must therefore survive untouched.
 *
 * Expected: [halt] status = 0x0000002B, CIA = 0xFFF00600,
 * DAR = 0x0FFFFFFC, DSISR = 0x00001E93 (manual bits 15-21 = 0b0000111,
 * which Table 5-15 decodes as lmw; bits 22-26 = 20 = rD, 27-31 = 19 = rA),
 * r20..r23 = A0..A3 unchanged, r08 = 0.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- install `sc` at the alignment vector ----------------------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0600
	lis	10, 0x4400
	ori	10, 10, 0x0002
	stw	10, 0(9)

	/* --- markers that a partial transfer would overwrite ------------ */
	li	20, 0xA0
	li	21, 0xA1
	li	22, 0xA2
	li	23, 0xA3

	/* --- arm the halt convention, then span the boundary ------------ */
	lis	0, 0x4600
	ori	0, 0, 0x0D1E
	li	3, 0x2B
	lis	19, 0x0FFF
	ori	19, 19, 0xFFFC		/* word-aligned, 4 bytes below 256 MB */
	lmw	20, 0(19)		/* 12 words = 48 bytes -> exception   */

	li	8, 0x99			/* must not execute                   */
	HALT(0)
