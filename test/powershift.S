/* powershift.S — the register-amount POWER shifts sle, sre, sleq, sreq,
 * slq, srq (MPC601UM Table 3-9, 601-only, hence `.machine "601"`).
 *
 * All six rotate rS and mask; what distinguishes them is where the bits
 * shifted in come from and what happens for a count of 32 or more:
 *   sle/sre    zeros in, no "32 or more" case; the rotated word goes to MQ
 *   sleq/sreq  the bits shifted in come from MQ, which then takes the
 *              rotated word
 *   slq/srq    like sle/sre but rB[26] means "32 or more", generating an
 *              all-zero mask so that rA is cleared (as slw/srw would)
 * Every case reads MQ back with mfspr from SPR 0 — it is not in the dump.
 *
 * Expected (hex): r04=12345678 r05=8 r06=34567800 r07=34567812 r08=00123456
 *   r09=78123456 r10=FFFFFFFF r11=345678FF r12=34567812 r13=FF123456
 *   r14=78123456 r15=00000028 r16=34567800 r17=0 r18=34567812 r19=00123456
 *   r20=0 r21=78123456 r22=0, XER = 0, CR = 20000000 (CR0 = EQ).
 */

#include "testlib.h"

	.text
	.machine "601"
	.globl _start
_start:
	lis	4, 0x1234
	ori	4, 4, 0x5678		/* r4 = 0x12345678                  */
	li	5, 8

	/* --- sle / sre: shift, and keep the rotated word in MQ --------- */
	sle	6, 4, 5			/* r4 << 8                          */
	mfspr	7, 0			/* MQ = ROTL(r4, 8)                 */
	sre	8, 4, 5			/* r4 >> 8                          */
	mfspr	9, 0			/* MQ = ROTL(r4, 24)                */

	/* --- sleq / sreq: the vacated bits come from MQ ---------------- */
	li	10, -1
	mtspr	0, 10			/* MQ = all ones                    */
	sleq	11, 4, 5		/* low byte from MQ                 */
	mfspr	12, 0			/* MQ then takes the rotated word   */
	mtspr	0, 10
	sreq	13, 4, 5		/* high byte from MQ                */
	mfspr	14, 0

	/* --- slq / srq: rB[26] set clears rA, MQ still gets the rotate - */
	li	15, 0x28		/* 40 = 8 with the "32 or more" bit */
	slq	16, 4, 5		/* as sle                           */
	slq	17, 4, 15		/* mask of all zeros -> 0           */
	mfspr	18, 0			/* rotated by 8 all the same        */
	srq	19, 4, 5		/* as sre                           */
	srq	20, 4, 15		/* -> 0                             */
	mfspr	21, 0
	srq.	22, 4, 15		/* 0 -> CR0 = EQ                    */

	HALT(0)
