/* lendian.S — little-endian mode, HID0[LM] (§2.4.3).
 *
 * The 601 does not byte-swap in little-endian mode; it XORs the low three
 * address bits by (8 - operand size).  So the same double word read three
 * ways gives three different answers, which is what the loads below check
 * against a pattern written in big-endian mode beforehand:
 *
 *     memory  0x4000: 11 22 33 44   0x4004: 55 66 77 88
 *     lwz  from 0x4000  -> PA 0x4004 -> 0x55667788
 *     lwz  from 0x4004  -> PA 0x4000 -> 0x11223344
 *     lbz  from 0x4000  -> PA 0x4007 -> 0x88
 *     lbz  from 0x4003  -> PA 0x4004 -> 0x55
 *     lhz  from 0x4000  -> PA 0x4006 -> 0x7788
 *
 * INSTRUCTION FETCH IS MUNGED TOO (§2.4.3.3): the two words of a double word
 * are swapped, so the instruction at address A comes from the word stored at
 * A xor 4.  Little-endian code therefore has to be laid out with each
 * aligned PAIR of instructions written in reverse order, which is what the
 * block below does — read the trailing comments, not the source order, for
 * what actually runs.  The `.align 3` and the leading nop put the mtspr that
 * enables the mode at an odd word, so that the first munged fetch is the
 * first instruction of an aligned pair.
 *
 * The last instruction is deliberately a misaligned load: in little-endian
 * mode ANY misaligned operand faults (§5.4.6.3), where big-endian mode would
 * have split it in hardware.  Two consequences are pinned by the expected
 * state.  DAR holds the effective address BEFORE munging (§2.4.3.1).  And
 * the handler word has to be stored at 0xFFF0_0604 rather than at the vector
 * itself, because exception entry does not leave little-endian mode — LM
 * lives in HID0, not in the MSR, so the handler is fetched munged like
 * everything else.
 *
 * SRR0 is worth a second look too: it is 0x0000_1064, the address the
 * faulting instruction was FETCHED FOR, not the 0x0000_1060 it is stored at.
 *
 * Expected: halt status 0x2A, CIA = 0xFFF00600, DAR = 0x00004001,
 * DSISR = 0x00000269 — the Table 5-13 image of 0x82690001: D-form, so manual
 * bits 15-21 are all zero, then bits 22-26 = 19 (rD) and 27-31 = 9 (rA).
 * r14 = 0x55667788, r15 = 0x11223344, r16 = 0x88, r17 = 0x55, r18 = 0x7788,
 * r19 = 0 (the faulting load was not performed).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- the alignment handler, at the vector XOR 4 ----------------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0604		/* 0xFFF00600 is fetched from here  */
	lis	10, 0x4400
	ori	10, 10, 0x0002		/* the `sc` instruction word        */
	stw	10, 0(9)

	/* --- the pattern, written big-endian ---------------------------- */
	li	9, 0x4000
	lis	4, 0x1122
	ori	4, 4, 0x3344
	stw	4, 0(9)
	lis	5, 0x5566
	ori	5, 5, 0x7788
	stw	5, 4(9)

	/* --- arm the halt convention while it is still easy ------------- */
	lis	0, 0x4600
	ori	0, 0, 0x0D1E
	li	3, 0x2A

	lis	6, 0x8001
	ori	6, 6, 0x0088		/* HID0 reset value with LM set     */

	.align	3
	nop				/* filler: put the mtspr at an odd   */
	mtspr	1008, 6			/*   word, so the pairs line up      */

	/* --- little-endian: each aligned PAIR is stored in reverse ------ */
	lwz	15, 4(9)		/* runs 2nd -> 0x11223344           */
	lwz	14, 0(9)		/* runs 1st -> 0x55667788           */
	lbz	17, 3(9)		/* runs 4th -> 0x55                 */
	lbz	16, 0(9)		/* runs 3rd -> 0x88                 */
	lwz	19, 1(9)		/* runs 6th -> alignment exception  */
	lhz	18, 0(9)		/* runs 5th -> 0x7788               */
