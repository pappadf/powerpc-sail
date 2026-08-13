/* bytereverse.S — lhbrx, lwbrx, sthbrx, stwbrx.
 *
 * 0x11223344 is written normally at 0x4000, read back byte-reversed, then
 * written back byte-reversed at 0x4008/0x400C and read normally, so both
 * directions are checked against the same value.
 *
 * Expected (hex): r04=11223344 r06=0 r07=44332211 r08=2211 r09=8
 *   r10=44332211 r11=C r12=44330000 r17=4000.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	17, 0x4000		/* scratch base                     */
	lis	4, 0x1122
	ori	4, 4, 0x3344
	stw	4, 0(17)		/* 0x4000: 11 22 33 44              */

	/* --- byte-reverse loads ----------------------------------------- */
	li	6, 0
	lwbrx	7, 17, 6		/* 44 33 22 11 -> 0x44332211        */
	lhbrx	8, 17, 6		/* 11 22 -> 0x00002211              */

	/* --- byte-reverse stores ---------------------------------------- */
	li	9, 8
	stwbrx	4, 17, 9		/* 0x4008: 44 33 22 11              */
	lwz	10, 8(17)
	li	11, 12
	sthbrx	4, 17, 11		/* 0x400C: 44 33 (low half only)    */
	lwz	12, 12(17)

	HALT(0)
