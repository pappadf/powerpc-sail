/* trace.S — the MSR[SE] trace exception (§5.4.12.2).
 *
 * The 601 has no trace vector at 0x00D00: single-step tracing shares the
 * run-mode vector 0x02000 (§5.4.12), so the one-word handler goes there.
 *
 * Two details this pins down.  The traced instruction COMPLETES before the
 * exception — r14 must hold its result — and SRR0 addresses the instruction
 * AFTER it (Table 5-25), not the traced one, which is the opposite of the
 * run-mode exception's SRR0 (see iabr.S).  MSR[SE] is also cleared by
 * exception entry (Table 5-6) while the saved copy in SRR1 still shows it
 * set, which is what lets an rfi resume tracing.
 *
 * The halt magic is armed BEFORE MSR[SE] is set: every instruction after
 * that point traces, so the setup must be finished first.
 *
 * Expected: halt status 0x2A, CIA = 0xFFF02000, SRR0 = the address of the
 * `li 15` below, SRR1 = 0x00001440 (MSR[16:31] with SE set), MSR = 0x00001040
 * (SE cleared on entry), r14 = 0x55, r15 = 0.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- install `sc` at the run mode / trace vector ---------------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x2000
	lis	10, 0x4400
	ori	10, 10, 0x0002
	stw	10, 0(9)

	/* --- arm the halt convention before tracing starts -------------- */
	lis	0, 0x4600
	ori	0, 0, 0x0D1E
	li	3, 0x2A

	/* --- enable single-step tracing --------------------------------- */
	mfmsr	11
	ori	12, 11, 0x0400		/* MSR[SE], manual bit 21           */
	mtmsr	12			/* SE was clear here: no trace yet  */

	li	14, 0x55		/* completes, THEN traces           */
	li	15, 0x99		/* must not execute                 */
	HALT(0)
