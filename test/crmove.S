/* crmove.S — mfcr, mtcrf and mcrxr.
 *
 * Three compares build a known CR, mfcr copies it out, mtcrf writes four
 * of the eight fields from a register (the other four must survive), and
 * mcrxr moves XER[0:3] into a field and clears them.
 *
 * CR walk:
 *   after the compares   0x82000004   cr0 = LT, cr1 = EQ, cr7 = GT
 *   after mtcrf 0xA5     0x12300608   fields 0,2,5,7 from 0x12345678,
 *                                     fields 1,3,4,6 unchanged
 *   after mcrxr cr3      0x123E0608   cr3 = SO|OV|CA|0 = 0xE
 *
 * Expected: CR = 0x123E0608, XER = 0, r04 = 0x82000004, r05 = 0x12345678,
 * r06 = 0x12300608, r07 = 0xE0000000, r08 = 0, r10 = 5.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	10, 5
	cmpwi	0, 10, 9		/* cr0 = LT */
	cmpwi	1, 10, 5		/* cr1 = EQ */
	cmpwi	7, 10, 1		/* cr7 = GT */

	mfcr	4			/* r4 = 0x82000004 */

	lis	5, 0x1234
	ori	5, 5, 0x5678
	mtcrf	0xA5, 5			/* mask 10100101: fields 0,2,5,7 */
	mfcr	6			/* r6 = 0x12300608 */

	lis	7, 0xE000		/* XER SO = OV = CA = 1 */
	mtxer	7
	mcrxr	3			/* cr3 = 0xE, XER[0:3] cleared */
	mfxer	8			/* r8 = 0 */

	HALT(0)
