/* ioseg.S — I/O controller interface segments, T = 1 (§6.10).
 *
 * Two halves.
 *
 * The first uses a memory-forced segment (BUID = 0x07F, §6.10.4): SR7 is
 * 0x87F0_0003, so an access anywhere in 0x7000_0000..0x7FFF_FFFF becomes an
 * ordinary memory access at SR[28:31] followed by the low 28 bits of the
 * effective address — EA 0x7000_1234 -> PA 0x3000_1234.  The first store is
 * made with MSR[DT] = 0, which is the point of it: on the 601 the T bit is
 * examined before MSR[DT] for data accesses (§6.5.2.2), so an I/O controller
 * interface segment translates with data translation switched off.  The
 * second store repeats it with MSR[DT] = 1 to show the two agree.
 *
 * The second half fetches from an I/O controller interface segment that is
 * NOT memory-forced (SR8 = 0x9000_0000, BUID = 0x100), which is an
 * instruction access exception (§6.8.2.2).  Instruction translation has to
 * be on for the fetch to consult the segment register at all, so BAT0 first
 * maps the low 8 MB one-to-one to keep the program running, and the branch
 * target is loaded into CTR because it is far out of a branch's reach.
 *
 * The 601 deviation this pins down is in SRR1: the architecture sets bit 3
 * for a fetch from a T = 1 segment and the 601 sets no bits at all
 * (Table 5-11, Table 6-3), so SRR1's high half must be zero.
 *
 * Expected: halt status 0x2A, CIA = 0xFFF00400, SRR0 = 0x80000000,
 * SRR1 = 0x00001060 (MSR[16:31] with IT set; high half all zero),
 * r14 = 0x11112222 and r15 = 0x33334444 read back from the physical
 * addresses the memory-forced segment produced, r17 = 0.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- install `sc` at the instruction access exception vector ---- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0400
	lis	10, 0x4400
	ori	10, 10, 0x0002
	stw	10, 0(9)

	/* --- SR7: T=1, Ks=Ku=0, BUID=0x07F (memory-forced), SR[28:31]=3 - */
	lis	4, 0x87F0
	ori	4, 4, 0x0003
	mtsr	7, 4

	/* --- store through it with data translation OFF ----------------- */
	lis	7, 0x1111
	ori	7, 7, 0x2222
	lis	4, 0x7000
	ori	4, 4, 0x1234
	stw	7, 0(4)			/* EA 0x7000_1234 -> PA 0x3000_1234 */

	/* --- and again with data translation ON ------------------------- */
	mfmsr	11
	ori	12, 11, 0x0010		/* MSR[DT] */
	mtmsr	12
	lis	8, 0x3333
	ori	8, 8, 0x4444
	lis	4, 0x7000
	ori	4, 4, 0x2000
	stw	8, 0(4)			/* EA 0x7000_2000 -> PA 0x3000_2000 */
	mtmsr	11

	/* --- read both back from the physical addresses ----------------- */
	lis	4, 0x3000
	ori	4, 4, 0x1234
	lwz	14, 0(4)
	lis	4, 0x3000
	ori	4, 4, 0x2000
	lwz	15, 0(4)

	/* --- BAT0: identity-map the low 8 MB so code survives MSR[IT]=1 - */
	li	4, 0x0002		/* BLPI = 0, PP = 10 (read/write)   */
	mtspr	528, 4
	li	4, 0x007F		/* PBN = 0, V = 1, BSM = 8 MB       */
	mtspr	529, 4

	/* --- SR8: T=1, BUID=0x100 — an ordinary I/O controller segment -- */
	lis	4, 0x9000
	mtsr	8, 4

	lis	4, 0x8000
	mtctr	4			/* fetch target, out of branch range */

	lis	0, 0x4600
	ori	0, 0, 0x0D1E		/* arm the halt magic                */
	li	3, 0x2A

	mfmsr	11
	ori	12, 11, 0x0020		/* MSR[IT] */
	mtmsr	12
	bctr				/* -> instruction access exception   */

	li	17, 0x99		/* must not execute                  */
	HALT(0)
