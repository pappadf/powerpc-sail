/* compare.S — the four integer compares.
 *
 * Each comparison targets a different CR field, so the single CR value in
 * the state dump records all eight results at once (there is no mfcr yet).
 * The last one runs with XER[SO] set, which every compare copies into the
 * SO bit of its field.
 *
 * Expected: CR = 0x84228449 — cr0 = LT, cr1 = GT, cr2 = EQ, cr3 = EQ,
 * cr4 = LT (signed), cr5 = GT (unsigned, same operands as cr4), cr6 = GT,
 * cr7 = LT|SO.  XER = 0x80000000, r04=1 r05=2 r06=FFFFFFFD r07=FFFFFFFF
 * r08=1 r09=80000000.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	4, 1
	li	5, 2
	li	6, -3
	li	7, -1
	li	8, 1

	cmp	0, 0, 4, 5		/* signed   1 <  2          -> LT */
	cmp	1, 0, 5, 4		/* signed   2 >  1          -> GT */
	cmp	2, 0, 4, 8		/* signed   1 == 1          -> EQ */
	cmpi	3, 0, 6, -3		/* SIMM is sign-extended    -> EQ */
	cmp	4, 0, 7, 8		/* signed   -1 < 1          -> LT */
	cmpl	5, 0, 7, 8		/* unsigned FFFFFFFF > 1    -> GT */
	cmpli	6, 0, 7, 0xFFFF		/* UIMM is zero-extended    -> GT */

	lis	9, 0x8000
	mtxer	9			/* XER[SO] = 1                    */
	cmp	7, 0, 4, 5		/* LT, with SO copied into cr7    */

	HALT(0)
