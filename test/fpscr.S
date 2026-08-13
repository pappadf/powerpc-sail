/* fpscr.S — floating-point compares and the FPSCR instructions
 * (MPC601UM Tables 3-14 and 3-15), ending in the floating-point enabled
 * program exception of §5.4.7.1.
 *
 * Every FPSCR reading is taken with mffs and stored, so the low word of each
 * snapshot is the register itself and the high word is the 601's x'FFFFFFFF'.
 * The sequence walks the register through, in order:
 *
 *   fcmpu with a QNaN   FPCC = FU only; an unordered fcmpu raises nothing
 *   fcmpo with an SNaN  VXSNAN, and VXVC too because VE = 0, plus FX and VX
 *   mcrfs               copies field 0 and clears the exception bits in it
 *                       (FX and OX), leaving VX standing on VXVC
 *   mtfsb0 x2           clearing the last invalid bit drops VX with it
 *   mtfsb1 3            setting OX sets FX by the usual 0 -> 1 rule
 *   mtfsfi 7,3          rounding mode = toward -infinity
 *   mtfsf 0x80,f1       field 0 written literally from a register: FX is
 *                       whatever the source says, here zero
 *   mtfsb1 24 then 7    an enabled invalid operation, which sets FEX but
 *                       invokes nothing while MSR[FE0] and MSR[FE1] are clear
 *
 * and then sets MSR[FE0] and raises it again, which does invoke the handler.
 *
 * Expected (hex): status 0x2A; r11=FFFFFFFF r12=00001000 r13=A1081000
 *   r14=21081000 r15=84211A00 r16=00001000 r17=90001000 r18=90001003
 *   r19=00001003 r20=E1001083, SRR1 = 0x00103840 (SRR1[11] = FP enabled,
 *   over an MSR with FP and FE0 set).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	mfmsr	3
	ori	3, 3, 0x2000		/* MSR[FP]                           */
	mtmsr	3
	li	10, 0x4000

	/* --- four operands: 1.0, 2.0, a QNaN and an SNaN --------------- */
	li	5, 0
	lis	4, 0x3FF0
	stw	4, 0(10)
	stw	5, 4(10)
	lfd	1, 0(10)
	lis	4, 0x4000
	stw	4, 8(10)
	stw	5, 12(10)
	lfd	2, 8(10)
	lis	4, 0x7FF8
	stw	4, 16(10)
	stw	5, 20(10)
	lfd	3, 16(10)
	lis	4, 0x7FF0
	li	6, 1
	stw	4, 24(10)
	stw	6, 28(10)		/* 0x7FF0000000000001: signaling      */
	lfd	4, 24(10)

	/* --- compares: one CR field each, and FPCC alongside ----------- */
	fcmpu	0, 1, 2			/* 1.0 < 2.0  -> FL                  */
	fcmpu	1, 2, 1			/* 2.0 > 1.0  -> FG                  */
	fcmpu	2, 1, 1			/* equal      -> FE                  */
	fcmpu	3, 1, 3			/* QNaN       -> FU, and nothing else */
	mffs	5
	stfd	5, 32(10)
	lwz	11, 32(10)		/* the 601's undefined high half     */
	lwz	12, 36(10)		/* FPCC = FU                         */

	fcmpo	4, 1, 4			/* SNaN: VXSNAN + VXVC (VE = 0)      */
	mffs	5
	stfd	5, 32(10)
	lwz	13, 36(10)

	mcrfs	5, 0			/* CR5 <- FX FEX VX OX; clears FX/OX */
	mffs	5
	stfd	5, 32(10)
	lwz	14, 36(10)
	mfcr	15			/* all six CR fields written so far  */

	/* --- clearing the invalid bits takes VX with them -------------- */
	mtfsb0	7			/* VXSNAN                            */
	mtfsb0	12			/* VXVC                              */
	mffs	5
	stfd	5, 32(10)
	lwz	16, 36(10)

	/* --- mtfsb1 sets FX by the usual rule; mtfsf writes it as given - */
	mtfsb1	3			/* OX -> FX follows                  */
	mffs	5
	stfd	5, 32(10)
	lwz	17, 36(10)
	mtfsfi	7, 3			/* RN = toward -infinity             */
	mffs	5
	stfd	5, 32(10)
	lwz	18, 36(10)
	mtfsf	0x80, 1			/* field 0 <- f1's low word = zero   */
	mffs	5
	stfd	5, 32(10)
	lwz	19, 36(10)

	/* --- an enabled exception with the MSR ignoring it ------------- */
	mtfsb1	24			/* VE                                */
	mtfsb1	7			/* VXSNAN: FEX, but no handler yet   */
	mffs	5
	stfd	5, 32(10)
	lwz	20, 36(10)

	/* --- and now with MSR[FE0] set, the same thing invokes it ------ */
	mtfsb0	7
	lis	23, 0xFFF0
	ori	23, 23, 0x0700		/* program exception vector          */
	lis	2, 0x4400
	ori	2, 2, 0x0002		/* the `sc` instruction word         */
	stw	2, 0(23)
	lis	0, 0x4600
	ori	0, 0, 0x0D1E		/* arm the halt magic                */
	li	3, 0x2A			/* status proving we got there       */
	mfmsr	4
	ori	4, 4, 0x0800		/* MSR[FE0], manual bit 20           */
	mtmsr	4
	mtfsb1	7			/* -> floating-point enabled program */
	li	21, 0x99		/* must not execute                  */

	HALT(0)
