/* align.S — the alignment exception (§5.4.6).
 *
 * With translation off, the only rule that fires is "a 256 MB boundary
 * crossing always faults" — every other misalignment the 601 splits in
 * hardware.  The first block therefore checks that ordinary misaligned
 * accesses complete normally, and the second crosses 0x1000_0000 with a
 * halfword and must trap.
 *
 * As in trap.S the handler is a single `sc` stored at the vector, so
 * reaching it halts with a recognisable status.
 *
 * Expected: [halt] status = 0x0000002A, CIA = 0xFFF00600,
 * SRR0 = the address of the faulting lhz, DAR = 0x0FFFFFFF,
 * DSISR = 0x000010F2 — manual bits 15-21 = 0b0001000, which Table 5-15
 * decodes as lhz, with bits 22-26 = 7 (rD) and 27-31 = 18 (rA).
 * r05 = 0x5500, r06 = 0x55000000, r07 = 0 (the load never completed),
 * r08 = 0 (the instruction after the fault did not run).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- install `sc` at the alignment vector 0xFFF0_0600 ----------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0600
	lis	10, 0x4400
	ori	10, 10, 0x0002
	stw	10, 0(9)

	/* --- misaligned, but nowhere near a 256 MB boundary: no fault --- */
	li	17, 0x4001
	li	4, 0x55
	stb	4, 0(17)		/* odd address                      */
	lhz	5, 0(17)		/* odd halfword  -> 0x5500          */
	lwz	6, 0(17)		/* odd word      -> 0x55000000      */

	/* --- arm the halt convention, then cross 0x1000_0000 ------------ */
	lis	0, 0x4600
	ori	0, 0, 0x0D1E
	li	3, 0x2A
	lis	18, 0x0FFF
	ori	18, 18, 0xFFFF		/* r18 = 0x0FFFFFFF                 */
	lhz	7, 0(18)		/* spans the boundary -> exception  */

	li	8, 0x99			/* must not execute                 */
	HALT(0)
