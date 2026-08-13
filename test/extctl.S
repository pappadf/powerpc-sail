/* extctl.S — eciwx and ecowx.
 *
 * Only two of the three paths through these instructions can be reached
 * without a device model:
 *
 *  1. EAR[E]=1 with the EA in an I/O controller interface segment
 *     (SR[T]=1) — the instruction is a no-op, so the target register keeps
 *     its old value and nothing else moves.
 *  2. EAR[E]=0 — a data access exception with DSISR[11] set and DAR
 *     holding the EA (MPC601UM Table 5-10).  That one halts, so it is
 *     last.
 *
 * The third path (a real device access) throws in the model.
 *
 * Expected: halt status 0x2A, DAR = 0x40000010, DSISR = 0x00100000,
 * SRR1 = 0x00001040, r04 = 0, r05 = 0x80000000, r06 = 0x1234 (untouched
 * by either no-op), r11 = 0x40000010, r14 = 0.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- EAR[E]=1, RID=5; SR7 marked as an I/O segment -------------- */
	lis	4, 0x8000
	ori	4, 4, 0x0005
	mtspr	282, 4			/* EAR */

	lis	5, 0x8000		/* segment register with T=1 */
	mtsr	7, 5

	li	6, 0x1234		/* sentinel: must survive both no-ops */
	lis	11, 0x7000		/* an address in segment 7 */
	eciwx	6, 0, 11
	ecowx	6, 0, 11

	/* --- EAR[E]=0 -> data access exception -------------------------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0300		/* data access exception vector */
	lis	10, 0x4400
	ori	10, 10, 0x0002		/* the sc instruction word */
	stw	10, 0(9)

	li	4, 0
	mtspr	282, 4			/* EAR[E] = 0 */

	lis	0, 0x4600
	ori	0, 0, 0x0D1E		/* arm the halt magic */
	li	3, 0x2A			/* status that proves we got there */

	lis	11, 0x4000
	ori	11, 11, 0x0010		/* an ordinary-segment address */
	eciwx	6, 0, 11
	li	14, 0x99		/* must not execute */
	HALT(0)
