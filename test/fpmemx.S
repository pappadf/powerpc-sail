/* fpmemx.S — the indexed and update floating-point memory forms
 * (MPC601UM Tables 3-22 and 3-23), and Rc=1 on the instructions that have it.
 *
 * test/fpmem.S covers the plain D-forms and the conversions; this one covers
 * the twelve addressing variants it does not — lfsx lfsux lfdx lfdux stfsx
 * stfsux stfdx stfdux and the D-form update pair lfsu/stfsu — each checked by
 * round-tripping 1.5 and by reading back the base register the update forms
 * write.  1.5 is 0x3FF8000000000000 as a double and 0x3FC00000 as a single,
 * so a single round trip through memory is exact and any confusion between
 * the two precisions is visible immediately.
 *
 * The tail exercises Rc=1, which for floating point copies FPSCR[FX FEX VX
 * OX] into CR1 rather than describing the result.  Only two of the four bits
 * can be set here: FX by the first inexact operation, and OX by the mtfsb1
 * that sets it directly.
 *
 * Expected (hex): r04=3FF80000 r05=3FF80000 r06=3FC00000 r07=3FF80000
 *   r08=3FC00000 r09=3FF80000 r18=3FC00000 r20=3FF80000
 *   r13=r14=00004010 r15=r16=00004008 r17=r19=00004018 (the update forms
 *   wrote the effective address back), r21=0 (CR1 clear), r22=08000000
 *   (FX after an inexact convert), r23=09000000 (FX and OX), r24=09000000,
 *   CR = 09000000.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	mfmsr	3
	ori	3, 3, 0x2000		/* MSR[FP]                           */
	mtmsr	3
	li	10, 0x4000
	li	11, 8
	li	12, 16
	li	3, 0

	/* --- 1.5, built through memory --------------------------------- */
	lis	4, 0x3FF8
	stw	4, 0(10)
	stw	3, 4(10)
	lfd	1, 0(10)

	/* --- double, indexed ------------------------------------------- */
	stfdx	1, 10, 11		/* -> 0x4008                         */
	lfdx	2, 10, 11
	stfd	2, 32(10)
	lwz	4, 32(10)

	/* --- double, indexed with update ------------------------------- */
	mr	13, 10
	stfdux	1, 13, 12		/* -> 0x4010, r13 <- 0x4010          */
	mr	14, 10
	lfdux	3, 14, 12		/* <- 0x4010, r14 <- 0x4010          */
	stfd	3, 32(10)
	lwz	5, 32(10)

	/* --- single, indexed ------------------------------------------- */
	stfsx	1, 10, 12		/* single 1.5 over 0x4010            */
	lwz	6, 16(10)
	lfsx	4, 10, 12
	stfd	4, 32(10)
	lwz	7, 32(10)

	/* --- single, indexed with update ------------------------------- */
	mr	15, 10
	stfsux	1, 15, 11		/* -> 0x4008, r15 <- 0x4008          */
	lwz	8, 8(10)
	mr	16, 10
	lfsux	5, 16, 11		/* <- 0x4008, r16 <- 0x4008          */
	stfd	5, 32(10)
	lwz	9, 32(10)

	/* --- single, D-form with update -------------------------------- */
	mr	17, 10
	stfsu	1, 24(17)		/* -> 0x4018, r17 <- 0x4018          */
	lwz	18, 24(10)
	mr	19, 10
	lfsu	6, 24(19)		/* <- 0x4018, r19 <- 0x4018          */
	stfd	6, 32(10)
	lwz	20, 32(10)

	/* --- Rc=1: CR1 takes FPSCR[FX FEX VX OX] ----------------------- */
	mtfsf	0xFF, 1			/* f1's low word is zero: FPSCR <- 0 */
	fmr.	7, 1
	fneg.	7, 7
	fabs.	7, 7
	fnabs.	7, 7
	frsp.	7, 1			/* 1.5 is exact in single precision  */
	mfcr	21			/* nothing raised yet                */
	fctiwz.	7, 1			/* 1.5 -> 1: inexact, so FX          */
	mfcr	22
	mtfsb1.	3			/* OX, directly                      */
	mfcr	23
	mtfsb0.	4			/* UX was not set anyway             */
	mtfsfi.	7, 0			/* rounding mode back to nearest     */
	mffs.	8
	mfcr	24

	HALT(0)
