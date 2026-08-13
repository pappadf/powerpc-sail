/* powershifti.S — the immediate and "long" POWER shifts sliq, sriq, slliq,
 * srliq, sllq, srlq (MPC601UM Table 3-9, 601-only).
 *
 * The first four are sle/sre/sleq/sreq with the amount in the SH field.  The
 * last two are the reason the family exists: paired with slq/srq they shift a
 * 64-bit quantity by any amount from 0 to 63 in two instructions, the first
 * leaving in MQ the bits that cross the word boundary and the second merging
 * them in without disturbing MQ.  This test runs that pair over
 * 0x123456789ABCDEF0 for counts of 8 and 40, which is what pins the ch. 10
 * sllq page's damaged "32 or more" case (see p601_insts_power.sail):
 *
 *   << 8  = 0x3456789ABCDEF000      >> 8  = 0x00123456789ABCDE
 *   << 40 = 0xBCDEF00000000000      >> 40 = 0x0000000000123456
 *
 * Expected (hex): r04=12345678 r05=9ABCDEF0 r06=34567800 r07=34567812
 *   r08=00123456 r09=78123456 r10=FFFFFFFF r11=345678FF r12=FF123456 r13=8
 *   r14=BCDEF000 r15=3456789A r16=28 r17=0 r18=BCDEF000 r19=00123456
 *   r20=789ABCDE r21=0 r22=00123456 r23=78123456, XER = 0, CR = 0.
 */

#include "testlib.h"

	.text
	.machine "601"
	.globl _start
_start:
	lis	4, 0x1234
	ori	4, 4, 0x5678		/* high word                        */
	lis	5, 0x9ABC
	ori	5, 5, 0xDEF0		/* low word                         */

	/* --- the immediate forms -------------------------------------- */
	sliq	6, 4, 8			/* as sle 8                         */
	mfspr	7, 0
	sriq	8, 4, 8			/* as sre 8                         */
	mfspr	9, 0
	li	10, -1
	mtspr	0, 10			/* MQ = all ones                    */
	slliq	11, 4, 8		/* as sleq 8: low byte from MQ      */
	mtspr	0, 10
	srliq	12, 4, 8		/* as sreq 8: high byte from MQ     */

	/* --- a 64-bit shift left, by 8 and then by 40 ------------------ */
	li	13, 8
	slq	14, 5, 13		/* low word, and MQ = ROTL(low, 8)  */
	sllq	15, 4, 13		/* high word, merging MQ's top byte */
	li	16, 40
	slq	17, 5, 16		/* count >= 32: low word is zero    */
	sllq	18, 4, 16		/* high word comes wholly from MQ   */

	/* --- and a 64-bit shift right, the same two counts ------------- */
	srq	19, 4, 13		/* high word, and MQ = ROTR(high,8) */
	srlq	20, 5, 13		/* low word, merging MQ's low byte  */
	srq	21, 4, 16		/* count >= 32: high word is zero   */
	srlq	22, 5, 16		/* low word comes wholly from MQ    */
	mfspr	23, 0			/* srlq left MQ alone               */

	HALT(0)
