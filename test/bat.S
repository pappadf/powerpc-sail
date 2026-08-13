/* bat.S — 601 block address translation (§6.7).
 *
 * Three BAT entries are programmed, data translation is turned on, and the
 * physical side is inspected afterwards with translation off again — which
 * is what makes the translation visible at all, since the dump shows only
 * registers.  Each entry exercises one part of §6.7.5:
 *
 *   BAT0  0x4000_0000 -> 0x0002_0000, 128 KB   the smallest block: BSM = 0,
 *                                              so the whole block logical
 *                                              page index must match
 *   BAT1  0x5000_0000 -> 0x0080_0000, 8 MB     BSM = 0b111111 masks the low
 *                                              six index bits out of the
 *                                              comparison and ORs them into
 *                                              the physical block number:
 *                                              EA 0x5040_0008 -> 0x00C0_0008
 *   BAT2  0x6000_0000 -> 0x0010_0000, 128 KB   PP = 0b11, read-only for
 *                                              either key (Table 6-8)
 *
 * A store into BAT2's block is the last thing the program does: it takes the
 * data access exception (§6.7.4), which a one-word handler at the vector
 * turns into a halt.
 *
 * Expected: halt status 0x2A, CIA = 0xFFF00300, DAR = 0x60000000,
 * DSISR = 0x0A000000 (manual bit 4 = protection violation, bit 6 = store),
 * SRR1 = 0x00001050 (MSR[16:31] with DT still set), r14 = 0xFEEDFACE (the
 * load from the read-only block was allowed), r15 = 0x11112222 and
 * r16 = 0x33334444 (read back from the physical addresses the two blocks
 * translate to), r17 = 0 (the instruction after the fault did not run).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- install `sc` at the data access exception vector ----------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0300
	lis	10, 0x4400
	ori	10, 10, 0x0002
	stw	10, 0(9)

	/* --- BAT0: 0x4000_0000 -> 0x0002_0000, 128 KB, read/write ------- */
	lis	4, 0x4000
	ori	4, 4, 0x0002		/* BLPI = 0x2000, WIM = 0, PP = 10  */
	mtspr	528, 4
	lis	4, 0x0002
	ori	4, 4, 0x0040		/* PBN = 0x0100, V = 1, BSM = 0     */
	mtspr	529, 4

	/* --- BAT1: 0x5000_0000 -> 0x0080_0000, 8 MB, read/write --------- */
	lis	4, 0x5000
	ori	4, 4, 0x0002
	mtspr	530, 4
	lis	4, 0x0080
	ori	4, 4, 0x007F		/* V = 1, BSM = 0b111111 (8 MB)     */
	mtspr	531, 4

	/* --- BAT2: 0x6000_0000 -> 0x0010_0000, 128 KB, read-only -------- */
	lis	4, 0x6000
	ori	4, 4, 0x0003		/* PP = 11: writes always prohibited */
	mtspr	532, 4
	lis	4, 0x0010
	ori	4, 4, 0x0040
	mtspr	533, 4

	/* --- seed the physical word the read-only block maps ------------ */
	lis	5, 0x0010
	lis	6, 0xFEED
	ori	6, 6, 0xFACE
	stw	6, 0(5)

	/* --- data translation on ---------------------------------------- */
	mfmsr	11
	ori	12, 11, 0x0010		/* MSR[DT] */
	mtmsr	12

	lis	7, 0x1111
	ori	7, 7, 0x2222
	lis	4, 0x4000
	stw	7, 4(4)			/* EA 0x4000_0004 -> PA 0x0002_0004 */

	lis	8, 0x3333
	ori	8, 8, 0x4444
	lis	4, 0x5040
	stw	8, 8(4)			/* EA 0x5040_0008 -> PA 0x00C0_0008 */

	lis	4, 0x6000
	lwz	14, 0(4)		/* read-only block: a load is fine  */

	/* --- translation off; look at the physical addresses ------------ */
	mtmsr	11
	lis	4, 0x0002
	lwz	15, 4(4)
	lis	4, 0x00C0
	lwz	16, 8(4)

	/* --- a store into the read-only block must fault ---------------- */
	mtmsr	12
	lis	0, 0x4600
	ori	0, 0, 0x0D1E		/* arm the halt magic               */
	li	3, 0x2A
	lis	4, 0x6000
	stw	7, 0(4)			/* -> data access exception         */

	li	17, 0x99		/* must not execute                 */
	HALT(0)
