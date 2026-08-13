/* lscbx.S — load string and compare byte indexed (MPC601UM ch. 10, §3.5.6),
 * the 601-only string load that stops on a byte equal to XER[CMPB].
 *
 * Covers the match and no-match cases (XER[BC] is rewritten only on a match,
 * and CR0 with Rc=1 reports the match in the EQ slot), the zero byte count
 * that makes no memory reference at all, the base register inside the loaded
 * range being skipped, and finally the alignment rule that is stricter than
 * every other string instruction's: a 4 KB crossing faults even when the
 * operand starts on a word boundary (§5.4.6.1.4).  That last case ends the
 * program through the one-word handler at the alignment vector, so the run
 * halts with status 0x2A and the dump also pins DAR and DSISR.
 *
 * The string at 0x4000 is 11 22 33 44 55 66 77 88.  XER = CMPB || BC as
 * 0x0000_ccbb, so 0x6608 means "stop at 0x66, eight bytes".
 *
 * Expected (hex): status 0x2A; r05=11223344 r06=55660000 (the match is the
 *   sixth byte, and the rest of that register is undefined-so-zero)
 *   r07=11223344 r08=55667788 r12=00006606 (BC = 6 bytes loaded)
 *   r13=20000000 (CR0 = match) r14=00009908 (BC untouched: no match)
 *   r15=0 r16=000005A5 (untouched by the zero-length form)
 *   r20=11223344 r21=00004000 (skipped: it is the base register)
 *   DAR = 0x00000FFC, DSISR = 0x00009312 (Table 5-13's image of the
 *   instruction: X-form, XO bits 01 0 0100, rD = 24, rA = 18).
 */

#include "testlib.h"

	.text
	.machine "601"
	.globl _start
_start:
	/* --- lay the string down at 0x4000 ----------------------------- */
	li	10, 0x4000
	lis	4, 0x1122
	ori	4, 4, 0x3344
	stw	4, 0(10)
	lis	4, 0x5566
	ori	4, 4, 0x7788
	stw	4, 4(10)
	li	11, 0			/* index register: EA = (r10) + 0   */

	/* --- a match stops the load and reports the count -------------- */
	li	3, 0x6608		/* CMPB = 0x66, BC = 8              */
	mtxer	3
	lscbx.	5, 10, 11		/* loads 6 bytes, the last matching */
	mfxer	12			/* BC = 6 now                       */
	mfcr	13			/* CR0 = 0b00 || match || SO        */

	/* --- no match: all eight bytes, and XER[BC] is left alone ------ */
	lis	3, 0
	ori	3, 3, 0x9908		/* CMPB = 0x99, BC = 8              */
	mtxer	3
	lscbx.	7, 10, 11
	mfxer	14			/* still 8                          */
	mfcr	15			/* CR0 = 0: no match                */

	/* --- a zero byte count loads nothing and cannot fault ---------- */
	li	16, 0x5A5		/* marker in rD                     */
	li	3, 0
	mtxer	3			/* BC = 0                           */
	lscbx	16, 10, 11		/* r16 survives                     */

	/* --- a base register inside the range is skipped --------------- */
	lis	3, 0
	ori	3, 3, 0x9908
	mtxer	3
	li	21, 0x4000		/* the base is also a target ...    */
	li	22, 0
	lscbx	20, 21, 22		/* ... so r21 keeps the address     */

	/* --- the 4 KB rule applies even to a word-aligned string ------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0600		/* alignment exception vector       */
	lis	2, 0x4400
	ori	2, 2, 0x0002		/* the `sc` instruction word        */
	stw	2, 0(9)
	lis	0, 0x4600
	ori	0, 0, 0x0D1E		/* arm the halt magic in r0         */
	li	3, 0x2A			/* status that proves we got there  */
	lis	17, 0
	ori	17, 17, 0x9908		/* BC = 8                           */
	mtxer	17
	li	18, 0x0FFC		/* word-aligned, but 0FFC+8 > 1000  */
	mfmsr	19
	ori	19, 19, 0x0010		/* MSR[DT] = 1: page address mode   */
	mtmsr	19
	lscbx	24, 18, 11		/* -> alignment exception           */
	li	12, 0x99		/* must not execute                 */

	HALT(0)
