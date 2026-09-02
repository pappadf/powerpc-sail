/* frspnan.S — frsp with NaN operands (MPCFPE32B §D.4.1, the QNaN and SNaN
 * cases of the round-to-single model).
 *
 * frsp is the one operation the architecture exempts from QNaN payload
 * propagation ("QNaNs propagate through all operations, except
 * floating-point round to single-precision, ordered comparison, and
 * conversion to integer" — MPCFPE32B §3.3.2): the delivered value is the
 * operand's single-precision image, its low 29 fraction bits cleared.
 *
 *   QNaN Operand:  frD <- frB[0-34] || 29 zeros
 *   SNaN Operand:  VXSNAN <- 1; if VE = 0 then
 *                  frD <- frB[0-11] || 1 || frB[13-34] || 29 zeros
 *
 * So frsp of QNaN 0x7FF8_0000_0002_BBBB is 0x7FF8_0000_0000_0000 — NOT the
 * operand unchanged — and frsp of SNaN 0x7FF4_0000_0002_BBBB is quietened
 * AND truncated: 0x7FFC_0000_0000_0000.  Identical on every core.
 *
 * FPSCR afterwards: the QNaN pass sets FPRF = QNaN (0b10001) and clears
 * FR/FI; the SNaN pass raises VXSNAN, whose 0->1 transition sets FX, and
 * VX summarizes it.  With VE = 0 nothing is enabled, so FEX = 0:
 *   FX | VX | VXSNAN | FPRF=10001  =  0xA1011000.
 *
 * Expected: r4/r5 = 7FF80000/00000000, r6/r7 = 7FFC0000/00000000,
 * r8 = A1011000.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	mfmsr	3
	ori	3, 3, 0x2000		/* MSR[FP]                          */
	mtmsr	3
	li	10, 0x4000

	/* --- QNaN 0x7FF800000002BBBB --------------------------------- */
	lis	4, 0x7FF8
	stw	4, 0(10)
	lis	5, 0x0002
	ori	5, 5, 0xBBBB
	stw	5, 4(10)
	lfd	1, 0(10)
	frsp	10, 1
	stfd	10, 8(10)
	lwz	4, 8(10)		/* 0x7FF80000                       */
	lwz	5, 12(10)		/* 0x00000000                       */

	/* --- SNaN 0x7FF400000002BBBB (same low word) ------------------ */
	lis	6, 0x7FF4
	stw	6, 0(10)
	lfd	2, 0(10)
	frsp	11, 2
	stfd	11, 16(10)
	lwz	6, 16(10)		/* 0x7FFC0000                       */
	lwz	7, 20(10)		/* 0x00000000                       */

	mffs	12
	stfd	12, 24(10)
	lwz	8, 28(10)		/* FPSCR = 0xA1011000               */
	HALT(0)
