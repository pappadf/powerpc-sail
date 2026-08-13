/* dcbz.S — Data Cache Block Set to Zero (§4.8.4).
 *
 * dcbz is the one cache instruction that changes memory rather than just
 * cache state, so it is the one a cache-less model still has to perform: it
 * clears the whole 32-byte sector containing the byte addressed by the EA.
 * The EA need not be aligned — the sector is derived by masking — so the
 * test aims at 0x4008 and checks that the whole of 0x4000..0x401F went to
 * zero while 0x4020 survived.
 *
 * The second half checks the exception the manual specifies instead of the
 * zeroing when the page cannot be established in the cache: "if the page
 * containing the byte addressed by EA is caching inhibited or write-through,
 * then the alignment exception handler is invoked".  A BAT with W = 1 puts a
 * block in write-through mode, so a dcbz there faults to 0xFFF0_0600.
 *
 * BAT0 maps 0x4000_0000 to 0x0002_0000 with WIM = 0b100 (W set), which makes
 * the upper BAT 0x4000_0042: BLPI = 0x2000, W = 1, PP = 0b10 (read/write).
 *
 * Expected: halt status 0x2A, CIA = 0xFFF00600, DAR = 0x40000000 (the EA,
 * not the masked sector address), DSISR = 0x00017C00.  That is the ordinary
 * Table 5-13 image of the instruction word 0x7C0027EC: manual bits 15-16 =
 * 0b10 and 17 = 1 from instruction bits 29-30 and 25, bits 18-21 = 0b1111
 * from instruction bits 21-24, and bits 22-31 zero because dcbz has no
 * source register and rA = 0 here.  Table 5-13 marks DSISR[22:26]
 * undefined for dcbz; the generic image is used there too.
 * r05 = r06 = r07 = 0 (the sector was cleared), r08 = 0x99999999 (the next
 * sector was not), r12 = 0.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- install `sc` at the alignment exception vector ------------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0600
	lis	10, 0x4400
	ori	10, 10, 0x0002
	stw	10, 0(9)

	/* --- fill 0x4000..0x4023 with a recognisable pattern ------------ */
	li	9, 0x4000
	lis	4, 0x9999
	ori	4, 4, 0x9999
	li	7, 0
1:	stwx	4, 7, 9
	addi	7, 7, 4
	cmpwi	7, 36
	blt	1b

	/* --- clear the sector holding 0x4008 ---------------------------- */
	li	10, 0x4008
	dcbz	0, 10

	lwz	5, 0(9)			/* first word of the sector    -> 0 */
	lwz	6, 16(9)		/* middle                      -> 0 */
	lwz	7, 28(9)		/* last word of the sector     -> 0 */
	lwz	8, 32(9)		/* the NEXT sector, untouched       */

	/* --- BAT0: 0x4000_0000 -> 0x0002_0000, 128 KB, write-through ---- */
	lis	4, 0x4000
	ori	4, 4, 0x0042		/* WIM = 100 (W set), PP = 10       */
	mtspr	528, 4
	lis	4, 0x0002
	ori	4, 4, 0x0040		/* PBN, V = 1, BSM = 0              */
	mtspr	529, 4

	mfmsr	11
	ori	11, 11, 0x0010		/* MSR[DT] */
	mtmsr	11

	lis	0, 0x4600
	ori	0, 0, 0x0D1E		/* arm the halt magic               */
	li	3, 0x2A
	lis	4, 0x4000
	dcbz	0, 4			/* W = 1 -> alignment exception     */

	li	12, 0x99		/* must not execute                 */
	HALT(0)
