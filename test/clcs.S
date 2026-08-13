/* clcs.S — cache line compute size (MPC601UM ch. 10, §4.8.1), the last of the
 * 601's POWER holdovers.
 *
 * rA is a selector, not a register number: 01100/01101/01110/01111 ask for the
 * instruction, data, minimum and maximum line sizes, and on the 601 all four
 * answer 64 (the cache line is 64 bytes, two 32-byte sectors — §1.2.3).  Every
 * other encoding returns an undefined value and Rc=1 leaves CR0 undefined, so
 * the model leaves rD and CR0 alone in those cases; the markers below and the
 * CR0 set by the compare are what show that.
 *
 * Expected (hex): r04=r05=r06=r07=40, r08=r09=r10=000005A5, r11=40,
 *   XER = 0, CR = 80000000 (CR0 = LT, set by the cmpwi and not disturbed by
 *   the clcs. that follows it).
 */

#include "testlib.h"

	.text
	.machine "601"
	.globl _start
_start:
	/* --- the four defined queries --------------------------------- */
	li	4, 0x5A5
	clcs	4, 12			/* instruction cache line size      */
	li	5, 0x5A5
	clcs	5, 13			/* data cache line size             */
	li	6, 0x5A5
	clcs	6, 14			/* minimum line size                */
	li	7, 0x5A5
	clcs	7, 15			/* maximum line size                */

	/* --- every other encoding is undefined: rD is left alone ------- */
	li	8, 0x5A5
	clcs	8, 0			/* 00xxx                            */
	li	9, 0x5A5
	clcs	9, 11			/* 010xx                            */
	li	10, 0x5A5
	clcs	10, 16			/* 1xxxx                            */

	/* --- Rc=1 leaves CR0 undefined, so the model keeps it ---------- */
	li	11, -1
	cmpwi	11, 0			/* CR0 = LT                         */
	.long	0x7D6C0427		/* clcs. 11,12 — 31 | 01011 | 01100 |
					   00000 | 531 | Rc=1; the assembler
					   has no syntax for the Rc form    */

	HALT(0)
