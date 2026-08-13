/* trap.S — tw and twi, and the program exception a taken trap raises.
 *
 * The first block runs every TO bit against operand pairs for which it is
 * false, including pairs where the signed and unsigned comparisons disagree;
 * all of them must fall through to the marker in r8.
 *
 * The second block takes a real trap.  After hard reset MSR[EP] = 1, so the
 * program-exception vector is 0xFFF0_0700 (MPC601UM Table 5-2); with address
 * translation off a plain stw can put an instruction there, so the test
 * installs a one-word handler — `sc` — and arms the halt convention before
 * trapping.  Reaching the handler therefore halts with status 0x2A.
 *
 * Expected: [halt] status = 0x0000002A, CIA = 0xFFF00700, SRR0 = the address
 * of the trapping tw, SRR1 = 0x00021040 (manual bit 14 = trap, plus
 * MSR[16:31] = ME|EP), r08 = 0x11 (all the non-trapping forms fell through),
 * r03 = 0x2A, r12 unchanged at 0 (the instruction after the trap did not run).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	4, 5
	li	5, 7
	li	6, -1
	li	7, 1

	/* --- conditions that are false: none of these may trap ---------- */
	tw	8, 4, 5			/* signed >   : 5 > 7 is false    */
	tw	4, 4, 5			/* equal      : false             */
	tw	1, 4, 5			/* unsigned > : false             */
	tw	8, 6, 7			/* signed >   : -1 > 1 is false   */
	tw	2, 6, 7			/* unsigned < : FFFFFFFF < 1 false*/
	twi	8, 6, -1		/* signed >   : -1 > -1 is false  */
	twi	1, 6, -1		/* unsigned > : equal, so false   */
	twi	16, 4, 3		/* signed <   : 5 < 3 is false    */
	twi	0, 4, 5			/* TO = 0 never traps             */

	li	8, 0x11			/* marker: everything fell through */

	/* --- install `sc` at the program-exception vector --------------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0700		/* 0xFFF00700                     */
	lis	10, 0x4400
	ori	10, 10, 0x0002		/* the sc instruction word        */
	stw	10, 0(9)

	/* --- arm the halt convention, then trap ------------------------- */
	lis	0, 0x4600
	ori	0, 0, 0x0D1E
	li	3, 0x2A			/* status proving the handler ran */
	tw	16, 4, 5		/* signed < : 5 < 7 -> TRAP       */

	li	12, 0x99		/* must not execute               */
	HALT(0)
