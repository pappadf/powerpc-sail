/* powersra.S — the POWER algebraic shifts sraiq, sraq and srea
 * (MPC601UM Table 3-9, 601-only).
 *
 * All three shift right algebraically, keep the rotated word in MQ, and set
 * XER[CA] to "a 1-bit was shifted out AND the value was negative" — the
 * srawi rule, which the positive case below pins by losing 1-bits without
 * setting CA.  sraq honours rB[26] ("32 or more" -> the result is all sign
 * bits) where srea ignores it and takes the whole count from rB[27:31]; the
 * pair with rB = 40 shows both halves of that difference, including the
 * opposite CA.
 *
 * Expected (hex): r04=FFFFFF00 r05=FFFFFFF0 r06=0 r07=0FFFFFF0 r08=FFFFFFFF
 *   r09=20000000 r10=7FFFFF00 r11=0007FFFF r12=0 r13=28 r14=FFFFFFFF
 *   r15=20000000 r16=00FFFFFF r17=0 r18=0 r19=FFFFFFFF r20=0 r21=00FFFFFF
 *   r22=0, XER = 0 (CA cleared by the last shift), CR = 20000000 (CR0 = EQ).
 */

#include "testlib.h"

	.text
	.machine "601"
	.globl _start
_start:
	lis	4, 0xFFFF
	ori	4, 4, 0xFF00		/* r4 = -256                        */
	lis	10, 0x7FFF
	ori	10, 10, 0xFF00		/* r10 = the same bits, positive    */

	/* --- sraiq: an immediate count -------------------------------- */
	sraiq	5, 4, 4			/* -256 >> 4 = -16, nothing lost    */
	mfxer	6			/* CA = 0                           */
	mfspr	7, 0			/* MQ = ROTL(r4, 28)                */
	sraiq	8, 4, 12		/* -1, and 1-bits were shifted out  */
	mfxer	9			/* CA = 1                           */
	sraiq	11, 10, 12		/* same bits lost, but positive     */
	mfxer	12			/* CA = 0: CA is ANDed with rS[0]   */

	/* --- sraq honours "32 or more", srea does not ------------------ */
	li	13, 0x28		/* 40 = 8 with the "32 or more" bit */
	sraq	14, 4, 13		/* all sign bits                    */
	mfxer	15			/* CA = 1: the whole value is lost  */
	mfspr	16, 0			/* MQ = ROTL(r4, 24) all the same   */
	sraq	17, 10, 13		/* positive -> 0                    */
	mfxer	18			/* CA = 0                           */
	srea	19, 4, 13		/* a count of 8: -256 >> 8 = -1     */
	mfxer	20			/* CA = 0: only sign bits lost      */
	mfspr	21, 0
	sraq.	22, 10, 13		/* 0 -> CR0 = EQ                    */

	HALT(0)
