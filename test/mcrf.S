/* mcrf.S — move condition register field.
 *
 * Three compares put three different patterns in cr3/cr5/cr7, and mcrf
 * copies each into another field, leaving every other field alone; the
 * fourth mcrf copies a field onto itself.  The dumped CR records all of it
 * (there is no mfcr yet).
 *
 * The last instruction is the invalid form the 601 nevertheless defines:
 * mcrf with the LK bit set executes normally and leaves the link register
 * "in an undefined state" (MPC601UM ch. 10 mcrf page).  The model's policy
 * for an undefined register result is to leave it unchanged, so LR must
 * still hold the value planted before it.  The assembler has no syntax for
 * the form, so the word is emitted directly:
 *   mcrf cr6,cr7 with LK=1 = 19 | 110 | 00 | 111 | 00 | 00000 | 0 | 1.
 *
 * Expected: CR = 0x82420488 (cr0 = cr7 = LT, cr1 = cr3 = EQ, cr2 = cr5 =
 * GT, cr4 = 0, cr6 = cr7 = LT), LR = 0x1234, r09 = 0x1234, r10 = 5.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	10, 5

	cmpwi	7, 10, 9		/* cr7 = LT */
	cmpwi	3, 10, 5		/* cr3 = EQ */
	cmpwi	5, 10, 1		/* cr5 = GT */

	mcrf	0, 7			/* cr0 = LT */
	mcrf	1, 3			/* cr1 = EQ */
	mcrf	2, 5			/* cr2 = GT */
	mcrf	4, 4			/* self-copy: cr4 stays 0 */

	li	9, 0x1234
	mtlr	9
	.long	0x4F1C0001		/* mcrf cr6,cr7 with LK=1 */

	HALT(0)
