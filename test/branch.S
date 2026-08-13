/* branch.S — the two decrement/condition forms of bc, an unconditional
 * branch, and SPR moves.  (The branch-to-register forms are in
 * branchreg.S.)
 *
 * Sums 4 + 3 + 2 + 1 in r5 with a bdnz loop, then uses a CR0 test to pick
 * between two values for r7.
 *
 * Expected: r4 = 0, r5 = r8 = 10, r6 = 4, r7 = 0xABC, CTR = 0, CR0 = GT.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	4, 4
	mtctr	4			/* CTR = 4   (mtspr 9) */
	mfctr	6			/* r6  = 4   (mfspr 9) */
	li	5, 0			/* accumulator         */

loop:
	add	5, 5, 4			/* r5 += r4            */
	addi	4, 4, -1		/* r4 -= 1             */
	bdnz	loop			/* bc 16,0,loop        */

	add.	8, 5, 0			/* r8 = 10, CR0 = GT   */
	beq	poison			/* not taken           */
	li	7, 0xABC
	b	done
poison:
	li	7, 0xBAD
done:
	HALT(0)
