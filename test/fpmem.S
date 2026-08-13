/* fpmem.S — floating-point loads, stores and moves (MPC601UM Tables 3-22,
 * 3-23, 3-24), plus the MSR[FP] gate that guards every one of them.
 *
 * dump_state() prints no FPRs, so every result is stored back to memory and
 * read into a GPR with lwz.  That is not just a workaround: it makes the
 * single-precision conversions of §3.5.9.1 and §3.5.10.1 directly visible,
 * which is most of what this test is for —
 *   1.5           = 0x3FF8000000000000 double, 0x3FC00000 single
 *   2^-149        = the smallest single denormal, 0x00000001, which is a
 *                   NORMAL double 0x36A0000000000000 once loaded
 *   2^-140        = 0x3730000000000000 double, which has to be denormalized
 *                   to be stored as the single 0x00000200
 *
 * The last two cases are the two halves of the conversion the manual states
 * as normalize/denormalize loops.
 *
 * Expected (hex): status 0x2A (the floating-point unavailable handler),
 *   r06=3FF80000 r07=0 r08=3FC00000 r09=3FF80000 r11=0 r13=36A00000 r14=0
 *   r12=1 r15=00000200 r16=BFF80000 r17=3FF80000 r18=BFF80000 r19=3FF80000
 *   r20=0 (a load with update and rA=0 does not update r0)
 *   r21=00000018 (a store with update and rA=0 does), r22=00004008,
 *   SRR1 = 0x1040 — the saved MSR with the high half cleared (Table 5-19).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- enable the floating-point unit ---------------------------- */
	mfmsr	3
	ori	3, 3, 0x2000		/* MSR[FP], manual bit 18            */
	mtmsr	3

	li	10, 0x4000		/* scratch area                      */

	/* --- a double round trip: 1.5 --------------------------------- */
	lis	4, 0x3FF8
	stw	4, 0(10)
	li	5, 0
	stw	5, 4(10)
	lfd	1, 0(10)
	stfd	1, 8(10)
	lwz	6, 8(10)		/* 0x3FF80000                        */
	lwz	7, 12(10)		/* 0                                 */

	/* --- double -> single -> double, all exact --------------------- */
	stfs	1, 16(10)
	lwz	8, 16(10)		/* 0x3FC00000                        */
	lfs	2, 16(10)
	stfd	2, 24(10)
	lwz	9, 24(10)		/* 0x3FF80000 again                  */
	lwz	11, 28(10)		/* 0                                 */

	/* --- the smallest single denormal loads as a normal double ----- */
	li	12, 1
	stw	12, 32(10)
	lfs	3, 32(10)		/* 2^-149                            */
	stfd	3, 40(10)
	lwz	13, 40(10)		/* 0x36A00000                        */
	lwz	14, 44(10)		/* 0                                 */

	/* --- storing 2^-140 single needs denormalization --------------- */
	lis	4, 0x3730
	stw	4, 48(10)
	li	5, 0
	stw	5, 52(10)
	lfd	4, 48(10)		/* f4 = 2^-140                       */
	stfs	4, 56(10)
	lwz	15, 56(10)		/* 0x00000200                        */

	/* --- moves: sign manipulation only ----------------------------- */
	fneg	5, 1
	stfd	5, 64(10)
	lwz	16, 64(10)		/* 0xBFF80000                        */
	fabs	6, 5
	stfd	6, 72(10)
	lwz	17, 72(10)		/* 0x3FF80000                        */
	fnabs	7, 1
	stfd	7, 80(10)
	lwz	18, 80(10)		/* 0xBFF80000                        */
	fmr	8, 1
	stfd	8, 88(10)
	lwz	19, 88(10)		/* 0x3FF80000                        */

	/* --- update forms, including the two rA=0 invalid forms -------- */
	/* A load with update and rA=0 loads but does not update r0, while a
	 * store with update and rA=0 does update it — the same asymmetry the
	 * integer forms have (ch. 10 lfsu and stfdu pages).  The assembler
	 * refuses to encode either, so both go in as words.               */
	.long	0xCD200008		/* lfdu f9,8(0): EA = 8, r0 kept     */
	mr	20, 0
	.long	0xDC200018		/* stfdu f1,0x18(0): r0 <- 0x18      */
	mr	21, 0
	li	22, 0x4000
	lfdu	10, 8(22)		/* r22 <- 0x4008                     */

	/* --- and with the FPU off, any of them faults (§5.4.8) --------- */
	lis	23, 0xFFF0
	ori	23, 23, 0x0800		/* FP unavailable vector             */
	lis	2, 0x4400
	ori	2, 2, 0x0002		/* the `sc` instruction word         */
	stw	2, 0(23)
	lis	0, 0x4600
	ori	0, 0, 0x0D1E		/* arm the halt magic                */
	li	3, 0x2A			/* status proving we got there       */
	mfmsr	4
	rlwinm	4, 4, 0, 19, 17		/* clear MSR[FP] (manual bit 18)     */
	mtmsr	4
	lfd	11, 0(10)		/* -> floating-point unavailable     */
	li	12, 0x99		/* must not execute                  */

	HALT(0)
