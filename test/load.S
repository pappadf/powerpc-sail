/* load.S — every integer load form: byte/halfword/word, zero- and
 * sign-extending, D-form, X-form and both update variants, plus the two
 * invalid update forms the 601 defines behaviour for.
 *
 * A pair of known words is stored at 0x4000 first, so the loads have
 * something big-endian to pick apart:
 *   0x4000: 11 22 33 44        0x4004: 88 99 AA BB
 *
 * Expected (hex): r04=11223344 r05=8899AABB r06=11 r07=44 r08=1122 r09=3344
 *   r10=FFFF8899 r11=1122 r12=8899AABB r13=4 r14=88 r15=8899 r16=FFFF8899
 *   r17=8899AABB r18=4000 r19=22 r20=3344 r21=8899AABB r22=FFFFFFFC
 *   r23=11223344 r24=88 r25=22 r26=22 r27=FFFF8899 r28=4000 r29=1122
 *   r30=4000 r31=4000.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	31, 0x4000		/* scratch base                     */
	lis	4, 0x1122
	ori	4, 4, 0x3344
	stw	4, 0(31)
	lis	5, 0x8899
	ori	5, 5, 0xAABB
	stw	5, 4(31)

	/* --- D-form loads ----------------------------------------------- */
	lbz	6, 0(31)		/* 0x11                             */
	lbz	7, 3(31)		/* 0x44                             */
	lhz	8, 0(31)		/* 0x1122                           */
	lhz	9, 2(31)		/* 0x3344                           */
	lha	10, 4(31)		/* 0x8899 -> sign-extended          */
	lha	11, 0(31)		/* 0x1122 -> positive               */
	lwz	12, 4(31)

	/* --- X-form loads ----------------------------------------------- */
	li	13, 4
	lbzx	14, 31, 13
	lhzx	15, 31, 13
	lhax	16, 31, 13
	lwzx	17, 31, 13

	/* --- update forms: rA walks along the data ---------------------- */
	mr	18, 31			/* cursor = 0x4000                  */
	lbzu	19, 1(18)		/* 0x22, cursor -> 0x4001           */
	lhzu	20, 1(18)		/* 0x3344, cursor -> 0x4002         */
	lwzu	21, 2(18)		/* 0x8899AABB, cursor -> 0x4004     */
	li	22, -4
	lwzux	23, 18, 22		/* 0x11223344, cursor -> 0x4000     */
	lbzux	24, 18, 13		/* 0x88, cursor -> 0x4004           */
	lhaux	25, 18, 22		/* 0x1122, cursor -> 0x4000         */

	mr	28, 31			/* second cursor = 0x4000           */
	lhau	27, 4(28)		/* 0xFFFF8899, cursor -> 0x4004     */
	lhzux	29, 28, 22		/* 0x1122, cursor -> 0x4000         */

	/* --- the two invalid update forms (§5.4.7; ch. 10 lbzu page) ----
	 * The 601 loads the data and suppresses the register update when
	 * rA = rD or rA = 0.  The assembler refuses to encode either, so the
	 * instruction words are written out by hand:
	 *   0x8F5A0001 = lbzu r26,1(r26)   (opcode 35, rD = rA = 26, d = 1)
	 *   0x8F200001 = lbzu r25,1(r0)    (opcode 35, rD = 25, rA = 0)   */
	mr	26, 31
	.long	0x8F5A0001		/* rA = rD: r26 gets the data, not EA */
	li	0, 0x4000
	.long	0x8F200001		/* rA = 0: r0 must keep 0x4000        */
	mr	30, 0			/* ... which this copies out          */

	HALT(0)
