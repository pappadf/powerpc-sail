/* iabr.S — the instruction address breakpoint / run mode exception
 * (§5.4.12.1, Tables 2-23/2-24).
 *
 * IABR (HID2) holds the address to compare against; HID1 says both which
 * compare to run and what to do on a match.  Here HID1 = 0x6080_0000:
 *   M  = 0b110 (manual bits 1-3)  full instruction address compare
 *   RM = 0b10  (manual bits 8-9)  trap to the run mode exception at 0x02000
 * Only RM = 10 is modellable — the other responses stop the processor's
 * clocks — and the two instruction-compare modes 010 and 110 differ only in
 * how much of the pipeline the compare sees, which is invisible here.
 *
 * Unlike the trace exception (see trace.S) the compare happens at decode and
 * the instruction does NOT execute: SRR0 addresses the breakpoint
 * instruction itself, and r15 must still be zero.
 *
 * IABR is written before HID1 so that the mtspr enabling the compare cannot
 * itself trip a stale breakpoint address.
 *
 * Expected: halt status 0x2A, CIA = 0xFFF02000, SRR0 = the address of `bp`,
 * SRR1 = 0x00001040, r14 = 0x55 (reached the breakpoint), r15 = 0 (the
 * breakpoint instruction never ran), r16 = 0.
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

	/* --- IABR = &bp ------------------------------------------------- */
	lis	4, bp@ha
	addi	4, 4, bp@l
	mtspr	1010, 4			/* HID2 = IABR                      */

	/* --- arm the halt convention ------------------------------------ */
	lis	0, 0x4600
	ori	0, 0, 0x0D1E
	li	3, 0x2A
	li	14, 0x55		/* proves we got this far           */

	/* --- enable: full instruction address compare -> run mode ------- */
	lis	4, 0x6080
	mtspr	1009, 4			/* HID1                             */

bp:	li	15, 0x99		/* must not execute                 */
	li	16, 0x77		/* nor this                         */
	HALT(0)
