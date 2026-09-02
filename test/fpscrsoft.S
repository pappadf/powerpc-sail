/* fpscrsoft.S — VXSOFT, VXSQRT and NI: the FPSCR bits whose existence is
 * per-core.
 *
 * The 601 does not implement manual bits 21 (VXSOFT), 22 (VXSQRT) or 29
 * (MPC601UM Table 2-1: "not implemented in the 601"): an mtfsb1 aimed at
 * them changes nothing — no sticky bit, no VX summary, no FX transition.
 * Every later core implements all three (MPCFPE32B Table 2-4; bit 29 is
 * NI), where VXSOFT and VXSQRT are ordinary invalid-operation exception
 * bits: the first 0->1 transition sets FX, and VX summarizes them.
 *
 * After mtfsb1 21; mtfsb1 22; mtfsb1 29:
 *   601:    FPSCR = 0x00000000
 *   later:  FX | VX | VXSOFT | VXSQRT | NI = 0xA0000604
 *
 * mcrfs 5,5 then copies FPSCR field 5 (manual bits 20-23) into cr5 and
 * clears the exception bits among them (VXSOFT, VXSQRT, VXCVI — FX is not
 * in the field and stays; VX is recomputed and falls):
 *   601:    cr5 = 0b0000, FPSCR = 0x00000000
 *   later:  cr5 = 0b0110, FPSCR = FX | NI = 0x80000004
 *
 * Expected: r4 = the first FPSCR image, r6 = CR (cr5 in bits 8-11),
 * r8 = the second FPSCR image.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	mfmsr	3
	ori	3, 3, 0x2000		/* MSR[FP]                          */
	mtmsr	3
	li	10, 0x4000

	mtfsb1	21			/* VXSOFT                           */
	mtfsb1	22			/* VXSQRT                           */
	mtfsb1	29			/* NI — sticky state, no FX         */
	mffs	5
	stfd	5, 0(10)
	lwz	4, 4(10)		/* 601: 0; later: 0xA0000604        */

	mcrfs	5, 5
	mfcr	6			/* 601: 0; later: 0x00000600        */
	mffs	7
	stfd	7, 8(10)
	lwz	8, 12(10)		/* 601: 0; later: 0x80000004        */
	HALT(0)
