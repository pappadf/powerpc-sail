/* branchreg.S — the XL-form branch-to-register instructions bclr[l] and
 * bcctr[l] (MPC601UM ch. 10 bclrx/bcctrx pages).
 *
 * Covers: bl/blr call+return, bclrl (LR is both the branch target and the
 * link destination), bdnzlr (the CTR-decrement form of bclr), bcctr with
 * both condition senses, bctrl, and the invalid bcctr form BO[2]=0 that
 * the 601 defines.
 *
 * Checks against an address are written as a subtraction so the recorded
 * value is 0 (or a small constant) rather than a link-time address.
 *
 * Expected: r4 = 0x42, r5 = 0, r6 = 3, r7 = 0x78, r8 = 0,
 *           r11 = 0xFFFFFFFF, CR0 = EQ.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	4, 0
	li	5, 0
	li	6, 0
	li	7, 0
	li	8, 0
	li	11, 0

	/* --- bl / blr: plain call and return (blr = bclr 20,0) ---------- */
	bl	setr4
	addi	4, 4, 1			/* r4 = 0x41 + 1                 */

	/* --- bclrl: target comes from the OLD LR, LR gets the new value - */
	lis	9, tB@ha
	addi	9, 9, tB@l
	mtlr	9
	bclrl	20, 0			/* branch always, and link       */
tBret:
	li	5, 0xBAD		/* skipped                       */
tB:
	mflr	5
	lis	9, tBret@ha
	addi	9, 9, tBret@l
	subf	5, 9, 5			/* r5 = 0 if LR = &tBret         */

	/* --- bdnzlr: bclr's CTR-decrement form, looping via LR ---------- */
	li	9, 3
	mtctr	9
	lis	9, loopC@ha
	addi	9, 9, loopC@l
	mtlr	9
loopC:
	addi	6, 6, 1
	bdnzlr				/* bclr 16,0: back while CTR != 0 */
					/* falls through with r6 = 3      */

	/* --- bcctr, both senses ---------------------------------------- */
	lis	9, tD@ha
	addi	9, 9, tD@l
	mtctr	9
	li	10, 5
	cmpwi	10, 5			/* CR0 = EQ                      */
	bnectr				/* bcctr 4,2 — not taken         */
	li	7, 0x77
	beqctr				/* bcctr 12,2 — taken            */
	li	7, 0xBAD		/* skipped                       */
tD:
	addi	7, 7, 1			/* r7 = 0x78                     */

	/* --- bctrl: LK on the CTR form --------------------------------- */
	lis	9, tE@ha
	addi	9, 9, tE@l
	mtctr	9
	bctrl
tEret:
	li	8, 0xBAD		/* skipped                       */
tE:
	mflr	8
	lis	9, tEret@ha
	addi	9, 9, tEret@l
	subf	8, 9, 8			/* r8 = 0 if LR = &tEret         */

	/* --- INVALID FORM: bcctr with BO[2]=0 (decrement and test CTR).
	 * The 601 tests the DECREMENTED CTR but fetches from the
	 * NONDECREMENTED one (ch. 10 bcctrx page).  CTR = &tF, so the
	 * decremented value is nonzero, the branch is taken to &tF, and
	 * CTR is left holding &tF - 1.
	 * The assembler rejects it ("invalid counter access"), so the word
	 * is emitted directly: bcctr 16,0 =
	 *   19 | BO=10000 | BI=00000 | 00000 | 528=1000010000 | LK=0.       */
	lis	9, tF@ha
	addi	9, 9, tF@l
	mtctr	9
	.long	0x4E000420		/* bcctr 16,0                    */
	li	11, 0xBAD		/* skipped                       */
tF:
	mfctr	11
	lis	9, tF@ha
	addi	9, 9, tF@l
	subf	11, 9, 11		/* r11 = -1 if CTR was decremented */

	/* Leave LR/CTR at a value that does not move when the test does. */
	li	9, 0
	mtlr	9
	mtctr	9
	HALT(0)

setr4:
	li	4, 0x41
	blr
