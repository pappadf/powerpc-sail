/* smoke.S — the model's original embedded smoke test as a real program:
 * integer arithmetic with a CR0 update, a store and a load back.
 *
 * Expected: r5 = r6 = 12, CR0 = GT.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	3, 5
	li	4, 7
	add.	5, 3, 4			/* r5 = 12, CR0 = GT */
	stw	5, 0x100(0)		/* MEM[0x100] = 12   */
	lwz	6, 0x100(0)		/* r6 = 12           */
	HALT(0)
