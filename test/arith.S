/* arith.S — the integer add/subtract family: the D-form "carrying"
 * instructions, the XO-form add/subf/addc/subfc/adde/subfe forms, the
 * extended (me/ze) forms, and neg.
 *
 * XER[CA] is sampled with mfxer where it matters, and set with mtxer where
 * an instruction consumes it, so that every carry-in is deterministic and
 * does not depend on the instruction before it.
 *
 * Expected (all hex): r04=5 r05=2 r06=20000000 r07=0 r08=FFFFFFFF r09=0
 *   r10=3 r11=7 r12=20000000 r13=1 r14=FFFFFFFF r15=2 r16=2 r17=1 r18=4
 *   r19=1 r20=1 r21=2 r22=0 r23=FFFFFFFF r24=0 r25=10(dec) r26=11(dec)
 *   r27=10(dec) r28=FFFFFFF6 r29=FFFFFFF5 r30=r31=r02=80000000 r01=0,
 *   XER = E0000000 (SO|OV|CA), CR = 30000000 (CR0 = EQ|SO).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- addic / subfic: D-form, always record XER[CA] -------------- */
	li	4, 5
	addic	5, 4, -3		/* r5  = 2; 5 + 0xFFFFFFFD carries  */
	mfxer	6			/* r6  = 0x20000000 (CA set)        */
	li	7, 0
	addic	8, 7, -1		/* r8  = 0xFFFFFFFF; no carry out   */
	mfxer	9			/* r9  = 0x00000000                 */
	li	10, 3
	subfic	11, 10, 10		/* r11 = 10 - 3 = 7; carries        */
	mfxer	12			/* r12 = 0x20000000                 */

	/* --- addc/adde: 0x1_FFFFFFFF + 0x2_00000002 = 0x4_00000001 ------ */
	li	13, 1			/* a high                           */
	li	14, -1			/* a low                            */
	li	15, 2			/* b high                           */
	li	16, 2			/* b low                            */
	addc	17, 14, 16		/* low  = 0x00000001, carry out     */
	adde	18, 13, 15		/* high = 1 + 2 + 1 = 4             */

	/* --- subfc/subfe: 0x2_00000000 - 0x1_00000001 = 0x0_FFFFFFFF ---- */
	li	19, 1			/* subtrahend high                  */
	li	20, 1			/* subtrahend low                   */
	li	21, 2			/* minuend high                     */
	li	22, 0			/* minuend low                      */
	subfc	23, 20, 22		/* low  = 0xFFFFFFFF, no carry      */
	subfe	24, 19, 21		/* high = 0x00000000, carry out     */

	/* --- addme/addze/subfme/subfze, each against XER[CA] = 1 -------- */
	lis	3, 0x2000		/* r3 = 0x20000000 = XER with CA=1  */
	li	25, 10
	mtxer	3
	addze	26, 25			/* 10 + 1         = 11              */
	mtxer	3
	addme	27, 25			/* 10 + 1 - 1     = 10              */
	mtxer	3
	subfze	28, 25			/* ~10 + 1        = -10             */
	mtxer	3
	subfme	29, 25			/* ~10 + 1 - 1    = -11             */

	/* --- neg: negating the most negative number returns it ---------- */
	lis	30, 0x8000		/* r30 = 0x80000000                 */
	neg	31, 30			/* r31 = 0x80000000; OE=0, no OV    */
	li	2, 0
	mtxer	2			/* clear XER, incl. the sticky SO   */
	nego	2, 30			/* r2  = 0x80000000; XER[OV,SO] = 1 */

	/* --- addic. records CR0 as well as the carry -------------------- */
	addic.	1, 10, -3		/* r1 = 0; CR0 = EQ|SO; carry out   */

	HALT(0)
