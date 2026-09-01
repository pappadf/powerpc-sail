/* ppc32bat.S — the architected split BAT arrays on the post-601 cores.
 *
 * NOT A 601 TEST: that core has ONE unified BAT array at SPRs 528-535 serving
 * both instruction and data accesses, keyed by Ks/Ku with the valid bit in the
 * lower register (MPC601UM §6.7, Figure 6-11).  These cores have FOUR
 * instruction entries at 528-535 and FOUR SEPARATE data entries at 536-543,
 * keyed by Vs/Vp in the upper register (MPCFPE32B §7.5).  The same SPR writes
 * therefore mean different things on the two, which is why test/bat.S is
 * excluded from these cores' manifests and this exists instead.
 *
 * The register values are derived from Table 7-9 and Figure 7-7/7-8:
 *
 *   upper = BEPI(0-14) | BL(19-29) | Vs(30) | Vp(31)
 *   lower = BRPN(0-14) | WIMG(25-28) | PP(30-31)
 *
 * DBAT0 maps effective 0x8000_0000 to physical 0x0002_0000, the smallest
 * block (128 KB, BL = 0), valid for supervisor accesses, read/write:
 *
 *   BEPI = 0x8000_0000 >> 17 = 0x4000, which sits in bits 0-14 and so is the
 *          word 0x8000_0000;
 *   BL   = 0 (128 KB, Table 7-10);
 *   Vs   = 1, Vp = 0  ->  0x2      =>  DBAT0U = 0x8000_0002
 *   BRPN = 0x0002_0000 >> 17 = 1, in bits 0-14  ->  0x0002_0000;
 *   WIMG = 0b0000; PP = 0b10 (read/write, Table 7-11)  ->  0x2
 *                                     =>  DBAT0L = 0x0002_0002
 *
 * PART 1 — the DBAT translates a DATA access.  0x5A5A5A5A is stored to
 * physical 0x0002_0000 and 0xA5A5A5A5 to 0x0002_0004 with translation off,
 * then read back through the block with MSR[DR] set.
 *   Expected r5 = 0x5A5A5A5A, r6 = 0xA5A5A5A5.
 *
 * PART 2 — an IBAT does NOT translate a data access, which is the whole point
 * of the split and the one thing the 601 cannot do.  IBAT0 is given the same
 * physical mapping for effective 0x9000_0000; a LOAD from there with MSR[DR]
 * set must miss the (empty) data array, fall through to page translation, and
 * fault, because SDR1 is zero and no PTE exists.
 *
 * That fault is a DSI (0x00300) with DAR holding the effective address and
 * DSISR bit 1 set — "set if the translation of an attempted access is not
 * found in the primary hash table entry group (HTEG), or in the rehashed
 * secondary HTEG, or in the range of a DBAT register" (MPC603EUM Table 4-2;
 * note "DBAT", not "BAT").  Manual bit 1 is 0x4000_0000; bit 6 stays clear
 * because this is a load.
 *
 * Expected: halt status 0x3B, CIA = 0xFFF00300, DAR = 0x90000000,
 * DSISR = 0x40000000, r5 = 0x5A5A5A5A, r6 = 0xA5A5A5A5, r12 = 0 (the
 * instruction after the faulting load must not run).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- install `sc` at the DSI vector ----------------------------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0300
	lis	10, 0x4400
	ori	10, 10, 0x0002
	stw	10, 0(9)

	/* --- seed physical 0x0002_0000 and 0x0002_0004 ------------------ */
	lis	9, 0x0002
	lis	4, 0x5A5A
	ori	4, 4, 0x5A5A
	stw	4, 0(9)
	lis	4, 0xA5A5
	ori	4, 4, 0xA5A5
	stw	4, 4(9)

	/* --- DBAT0: 0x8000_0000 -> 0x0002_0000, 128 KB, supervisor r/w -- */
	lis	4, 0x8000
	ori	4, 4, 0x0002		/* BEPI, BL = 0, Vs = 1, Vp = 0     */
	mtspr	536, 4
	lis	4, 0x0002
	ori	4, 4, 0x0002		/* BRPN, WIMG = 0, PP = 10          */
	mtspr	537, 4

	/* --- IBAT0: 0x9000_0000 -> 0x0002_0000, instruction side only --- */
	lis	4, 0x9000
	ori	4, 4, 0x0002
	mtspr	528, 4
	lis	4, 0x0002
	ori	4, 4, 0x0002
	mtspr	529, 4

	/* --- PART 1: read back through the data block ------------------- */
	mfmsr	11
	ori	11, 11, 0x0010		/* MSR[DR]                          */
	mtmsr	11

	lis	9, 0x8000
	lwz	5, 0(9)
	lwz	6, 4(9)

	/* --- PART 2: the instruction block must not serve a load -------- */
	lis	0, 0x4600
	ori	0, 0, 0x0D1E		/* arm the halt magic               */
	li	3, 0x3B
	lis	9, 0x9000
	lwz	7, 0(9)			/* no DBAT covers this -> DSI       */

	li	12, 0x99		/* must not execute                 */
	HALT(0)
