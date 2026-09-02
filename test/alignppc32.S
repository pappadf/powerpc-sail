/* alignppc32.S — the post-601 alignment rules (§4.5.6 in the MPC603EUM,
 * MPC604UM, MPC604EUM and MPC750UM), which are DISJOINT from the 601's.
 *
 * None of these cores has the 601's blanket 256 MB rule: "the 604 provides
 * hardware support for misaligned storage accesses" (MPC604UM §4.5.6), and
 * the MPC603EUM's Table 4-15 lists page-address translation as the ONLY
 * access type with a boundary rule.  So the misaligned lhz/lwz across
 * 0x10000000 below — which trap on a 601 (align.S) — complete normally.
 *
 * What DOES fault, on every one of the four, is a floating-point load or
 * store that is not word-aligned, whatever it crosses, so the program ends
 * with `lfs` at an odd EA and halts at the alignment vector.  DAR gets the
 * EA itself on all four (the 603e's +4 quirk names only lmw/stmw/lwarx/
 * stwcx., MPC603EUM §4.5.6.2).
 *
 * Expected: r7 = 0x6677 and r8 = 0x66770000 (the seeded bytes read across
 * the boundary), halt status 0x2A at the alignment vector,
 * SRR0 = the lfs, DAR = 0x4001, r12 = 0 (the instruction after the fault
 * did not run).  Not run on the 601, whose rules align.S covers.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- install `sc` at the alignment vector 0xFFF0_0600 --------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0600
	lis	10, 0x4400
	ori	10, 10, 0x0002
	stw	10, 0(9)

	/* --- misaligned loads across 0x1000_0000: no fault here ------- */
	lis	4, 0x0FFF
	ori	4, 4, 0xFFFF		/* r4 = 0x0FFFFFFF                  */
	li	5, 0x66
	stb	5, 0(4)			/* last byte below the boundary     */
	li	6, 0x77
	stb	6, 1(4)			/* first byte above it              */
	lhz	7, 0(4)			/* -> 0x6677, spans the boundary    */
	lwz	8, 0(4)			/* -> 0x66770000, spans it too      */

	/* --- misaligned floating-point load: always a fault ----------- */
	mfmsr	3
	ori	3, 3, 0x2000		/* MSR[FP]                          */
	mtmsr	3
	lis	0, 0x4600
	ori	0, 0, 0x0D1E
	li	3, 0x2A
	li	11, 0x4001
	lfs	1, 0(11)		/* odd EA -> alignment exception    */

	li	12, 0x99		/* must not execute                 */
	HALT(0)
