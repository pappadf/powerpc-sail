/* string.S — lswi, lswx, stswi, stswx.
 *
 * The source bytes at 0x4000 are 11 22 33 44 55 66 77 88, so a transfer of
 * n bytes has an obvious expected value for every n, and a partly filled
 * last register shows its low-order bytes cleared.
 *
 * Also covered: the zero-length lswx/stswx forms, which the 601 executes as
 * no-ops that touch neither memory nor rD, and a load whose base register
 * lies in the range being loaded, where the base must survive (§3.5.6).
 *
 * Expected (hex): r04=11223344 r05=55667788 r06=3 r07=0 r08=11223344
 *   r09=55000000 r10=0 r11=0 r12=0 r13=5A5 r14=8 r15=0 r16=6 r17=4000
 *   r18=4020 r19=4030 r20=11223344 r21=55660000 r22=11223300 r23=0
 *   r24=4000 r25=55667788 r26=4040 r27=0 r28=11223344 r29=55660000,
 *   XER = 8.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	17, 0x4000		/* source base                      */
	lis	4, 0x1122
	ori	4, 4, 0x3344
	stw	4, 0(17)
	lis	5, 0x5566
	ori	5, 5, 0x7788
	stw	5, 4(17)

	/* --- lswi: 6 bytes fill r20 and two thirds of r21 --------------- */
	lswi	20, 17, 6

	/* --- lswx: byte count comes from XER[BC] ------------------------ */
	li	6, 3
	mtxer	6
	li	7, 0
	lswx	22, 17, 7		/* 3 bytes -> 0x11223300            */

	/* --- stswi: 5 bytes out of r20/r21, read back ------------------- */
	li	18, 0x4020
	stswi	20, 18, 5
	lwz	8, 0(18)
	lwz	9, 4(18)		/* 55 __ __ __                      */

	/* --- zero-length stswx touches no memory ------------------------ */
	li	10, 0
	mtxer	10
	li	19, 0x4030
	li	11, 0
	stswx	20, 19, 11
	lwz	12, 0(19)		/* still zero                       */

	/* --- zero-length lswx leaves rD alone --------------------------- */
	li	13, 0x5A5
	lswx	13, 17, 11

	/* --- stswx: 6 bytes out of r20/r21 ------------------------------ */
	li	16, 6
	mtxer	16
	li	26, 0x4040
	li	27, 0
	stswx	20, 26, 27
	lwz	28, 0(26)
	lwz	29, 4(26)		/* 55 66 __ __                      */

	/* --- base register inside the loaded range is not loaded --------
	 * The assembler rejects rD = rA ("source and target register
	 * operands must be different"), so the word is written by hand:
	 *   0x7F187C2A = lswx r24,r24,r15  (XO 533, rD = rA = 24, rB = 15) */
	li	24, 0x4000
	li	14, 8
	mtxer	14
	li	15, 0
	.long	0x7F187C2A		/* r24 keeps the address; r25 loads  */

	HALT(0)
