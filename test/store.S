/* store.S — every integer store form: byte/halfword/word, D-form, X-form
 * and both update variants, plus the rA = 0 update form that the 601
 * executes rather than treating as invalid.
 *
 * Each group stores into a fresh part of the scratch area and reads a whole
 * word back, so untouched bytes (which read as zero) show exactly how far
 * each store reached.
 *
 * Expected (hex): r04=11223344 r05=44003344 r06=11223344 r07=10 r08=AABBCCDD
 *   r09=12 r10=14 r11=DD00CCDD r12=AABBCCDD r13=4024 r14=00443344
 *   r15=11223344 r16=4 r17=403C r18=DD000000 r19=CCDD0000 r20=AABBCCDD
 *   r21=4044 r22=11223344 r31=4000.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	31, 0x4000		/* scratch base                     */
	lis	4, 0x1122
	ori	4, 4, 0x3344		/* r4 = 0x11223344                  */

	/* --- D-form stores: 0x4000 gets 44 __ 33 44 --------------------- */
	stb	4, 0(31)
	sth	4, 2(31)
	stw	4, 4(31)
	lwz	5, 0(31)
	lwz	6, 4(31)

	/* --- X-form stores: 0x4010 gets DD __ CC DD --------------------- */
	li	7, 0x10
	lis	8, 0xAABB
	ori	8, 8, 0xCCDD		/* r8 = 0xAABBCCDD                  */
	stbx	8, 31, 7
	li	9, 0x12
	sthx	8, 31, 9
	li	10, 0x14
	stwx	8, 31, 10
	lwz	11, 0x10(31)
	lwz	12, 0x14(31)

	/* --- D-form update stores: cursor walks 0x4020 -> 0x4024 -------- */
	li	13, 0x4020
	stbu	4, 1(13)		/* 0x44 at 0x4021                   */
	sthu	4, 1(13)		/* 0x3344 at 0x4022                 */
	stwu	4, 2(13)		/* 0x11223344 at 0x4024             */
	lwz	14, 0x20(31)
	lwz	15, 0x24(31)

	/* --- X-form update stores: 0x4034, 0x4038, 0x403C --------------- */
	li	16, 4
	li	17, 0x4030
	stbux	8, 17, 16
	sthux	8, 17, 16
	stwux	8, 17, 16
	lwz	18, 0x34(31)
	lwz	19, 0x38(31)
	lwz	20, 0x3C(31)

	/* --- store with update and rA = 0 -------------------------------
	 * The architecture calls this form invalid and the assembler refuses
	 * it, but the ch. 10 stwu page says the 601 "supports execution with
	 * rA=0 as shown above" — so r0 IS updated, unlike the loads.
	 *   0x94800004 = stwu r4,4(r0)  (opcode 37, rS = 4, rA = 0, d = 4) */
	li	0, 0x4040
	.long	0x94800004
	mr	21, 0			/* 0x4044 if the update happened    */
	lwz	22, 0x44(31)

	HALT(0)
