/* multiple.S — lmw and stmw, including the invalid form where the base
 * register is inside the range being loaded.
 *
 * r28..r31 are stored out with stmw, the registers cleared, and the words
 * loaded back with lmw.  The last lmw uses rD = rA = 20: r20 must survive
 * as the base address while r21..r31 are loaded from memory, which is the
 * 601's documented behaviour for that form (ch. 10 lmw page).  Words above
 * 0x402C were never written, so they read as zero.
 *
 * Expected (hex): r02=4020 r13=AA r14=DD r15=AA r16=DD r20=4020 r21=BB
 *   r22=CC r23=DD, r24..r31 = 0.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	2, 0x4020		/* scratch base                     */
	li	28, 0xAA
	li	29, 0xBB
	li	30, 0xCC
	li	31, 0xDD
	stmw	28, 0(2)		/* four words at 0x4020..0x402F     */
	lwz	13, 0(2)
	lwz	14, 12(2)

	li	28, 0
	li	29, 0
	li	30, 0
	li	31, 0
	lmw	28, 0(2)		/* load them back                   */
	mr	15, 28
	mr	16, 31

	/* --- rD = rA: the base register is skipped in the load ----------
	 * The assembler rejects this form ("index register in load range"),
	 * so the word is written out by hand:
	 *   0xBA940000 = lmw r20,0(r20)  (opcode 46, rD = rA = 20, d = 0) */
	li	20, 0x4020
	.long	0xBA940000		/* r20 keeps the address; r21.. load */

	HALT(0)
