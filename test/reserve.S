/* reserve.S — lwarx and stwcx. (§3.5.7).
 *
 * Three scenarios, in order:
 *
 *   1. lwarx then stwcx. — the store happens and CR0[EQ] is set.
 *   2. stwcx. again with no reservation left (the first one consumed it) —
 *      no store, CR0[EQ] clear, and no exception of any kind.
 *   3. lwarx, then an instruction that takes an exception, then stwcx. —
 *      "execution of an instruction that causes an exception" is one of
 *      §3.5.7's ways to lose a reservation, so this store must fail too.
 *      A one-word `rfi` at the system call vector gets control back.
 *
 * CR0 after a conditional store is 0b00 || store_performed || XER[SO], so a
 * whole-CR read is 0x20000000 when it worked and 0 when it did not.
 *
 * Expected: halt status 0, r05 = 0x12345678 (what lwarx loaded),
 * r10 = 0x20000000 and r11 = 0xAAAABBBB (scenario 1 stored),
 * r12 = 0 and r13 = 0xAAAABBBB (scenario 2 did not),
 * r14 = 0xAAAABBBB (the second lwarx), r15 = 0 and r16 = 0xAAAABBBB
 * (scenario 3 did not store either).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- a one-word `rfi` handler at the system call vector --------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0C00
	lis	10, 0x4C00		/* rfi = 0x4C000064 */
	ori	10, 10, 0x0064
	stw	10, 0(9)

	/* --- seed the semaphore word ------------------------------------ */
	li	9, 0x4000
	lis	4, 0x1234
	ori	4, 4, 0x5678
	stw	4, 0(9)

	/* --- (1) reserve, then store conditionally ---------------------- */
	lwarx	5, 0, 9
	lis	6, 0xAAAA
	ori	6, 6, 0xBBBB
	stwcx.	6, 0, 9			/* succeeds                         */
	mfcr	10
	lwz	11, 0(9)

	/* --- (2) no reservation: no store, no exception ----------------- */
	stwcx.	4, 0, 9			/* fails                            */
	mfcr	12
	lwz	13, 0(9)

	/* --- (3) an exception in between clears the reservation --------- */
	lwarx	14, 0, 9
	li	0, 0			/* NOT the halt magic               */
	sc				/* -> system call exception -> rfi  */
	stwcx.	4, 0, 9			/* fails: the exception cleared it  */
	mfcr	15
	lwz	16, 0(9)

	HALT(0)
