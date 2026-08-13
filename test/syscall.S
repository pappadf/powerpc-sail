/* syscall.S — the three ways the 601's sc differs from the architecture's
 * (MPC601UM ch. 10 SC page, POWER compatibility note).
 *
 * A one-word rfi handler at the system call vector returns from each one,
 * so all four can run in a single program and SRR1 can be sampled after
 * each.  SRR1 = <instruction bits 16-31> || <MSR bits 16-31>, and MSR is
 * 0x1040 (ME|EP) throughout.
 *
 * The last three sc words are written out with .long: the assembler emits
 * only the architectural 0x44000002.
 *
 *   sc            0x44000002   SRR1 = 0x00021040
 *   .long ..1F5A  bits 16-29 carry a POWER svc immediate
 *   .long ..3C58  bit 30 clear — reserved in the architecture, ignored
 *                 by the 601, so this still executes as a system call
 *   .long ..0003  LK set — an invalid form the 601 executes AND links
 *
 * Expected: r04 = 0x00021040, r05 = 0x1F5A1040, r06 = 0x3C581040,
 * r08 = 0 (LR held the address after the linking sc), r11 = 0x00031040.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	lis	9, 0xFFF0
	ori	9, 9, 0x0C00		/* system call vector */
	lis	10, 0x4C00
	ori	10, 10, 0x0064		/* the rfi instruction word */
	stw	10, 0(9)

	li	0, 0			/* not the halt magic: real sc */

	sc
	mfsrr1	4

	.long	0x44001F5A		/* sc, bits 16-29 = 0x07D6 */
	mfsrr1	5

	.long	0x44003C58		/* sc with bit 30 = 0 */
	mfsrr1	6

	li	7, 0
	mtlr	7			/* LR must be written by the sc */
	.long	0x44000003		/* sc with LK = 1 */
lk_ret:
	mfsrr1	11
	mflr	8
	lis	9, lk_ret@ha
	addi	9, 9, lk_ret@l
	subf	8, 9, 8			/* 0 if LR = &lk_ret */

	HALT(0)
