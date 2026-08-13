/* pagetable.S — hashed page table translation (§6.8, §6.9).
 *
 * The program builds a two-entry page table by hand, turns data translation
 * on, touches two pages through it, and then inspects the physical side —
 * including the reference and change bits the walk wrote back into the PTEs.
 *
 * Segment 2 holds VSID 0x000123 and the table lives at physical 0x0010_0000
 * with HTABMASK = 0, the minimum 64 KB / 1024 PTEGs.  With that mask the
 * PTEG address is HTABORG followed by the low ten bits of the hash and six
 * zeros, so both PTEG addresses below follow from the hash alone
 * (§6.9.1.3–4):
 *
 *   EA 0x2000_3000  page index 0x0003  hash  0x00123 ^ 0x00003 = 0x00120
 *                   -> PRIMARY   PTEG at 0x0010_4800, PPN 0x00042
 *   EA 0x2000_4000  page index 0x0004  hash  0x00123 ^ 0x00004 = 0x00127,
 *                   complemented to 0x7FED8 for the secondary hash
 *                   -> SECONDARY PTEG at 0x0010_B600, PPN 0x00043
 *
 * The second entry is placed in its secondary PTEG with H = 1 so that the
 * search has to fail over the whole primary group before finding it.
 *
 * A store goes to the first page and a load to the second, so afterwards the
 * first PTE must carry both R and C and the second only R (§6.8.4).  The
 * program then reads an address in a third page that has no PTE at all,
 * which is the page-fault path.
 *
 * Expected: halt status 0x2A, CIA = 0xFFF00300, DAR = 0x20005000,
 * DSISR = 0x40000000 (manual bit 1 = page fault, bit 6 clear for a load),
 * SRR1 = 0x00001050, r14 = 0xC0FFEE00 (loaded through the secondary-hash
 * page), r15 = 0xDEADBEEF (stored through the primary-hash page and read
 * back physically), r16 = 0x00042182 (PTE word 1 with R and C set),
 * r17 = 0x00043102 (R set, C clear), r18 = r19 = 0.
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

	/* --- page table at physical 0x0010_0000, 64 KB (HTABMASK = 0) --- */
	lis	4, 0x0010
	mtspr	25, 4			/* SDR1 */

	li	4, 0x0123
	mtsr	2, 4			/* SR2: T = 0, Ks = Ku = 0, VSID     */

	/* --- PTE for page 0x2000_3000, primary PTEG at 0x0010_4800 ------ */
	lis	5, 0x0010
	ori	5, 5, 0x4800
	lis	4, 0x8000
	ori	4, 4, 0x9180		/* V=1, VSID=0x000123, H=0, API=0   */
	stw	4, 0(5)
	lis	4, 0x0004
	ori	4, 4, 0x2002		/* PPN=0x00042, R=C=0, PP=10        */
	stw	4, 4(5)

	/* --- PTE for page 0x2000_4000, secondary PTEG at 0x0010_B600 ---- */
	lis	6, 0x0010
	ori	6, 6, 0xB600
	lis	4, 0x8000
	ori	4, 4, 0x91C0		/* V=1, VSID=0x000123, H=1, API=0   */
	stw	4, 0(6)
	lis	4, 0x0004
	ori	4, 4, 0x3002		/* PPN=0x00043                      */
	stw	4, 4(6)

	/* --- seed the second physical page ------------------------------ */
	lis	7, 0x0004
	ori	7, 7, 0x3008
	lis	4, 0xC0FF
	ori	4, 4, 0xEE00
	stw	4, 0(7)

	/* --- data translation on ---------------------------------------- */
	mfmsr	11
	ori	12, 11, 0x0010		/* MSR[DT] */
	mtmsr	12

	lis	4, 0x2000
	ori	4, 4, 0x3010
	lis	8, 0xDEAD
	ori	8, 8, 0xBEEF
	stw	8, 0(4)			/* -> PA 0x0004_2010; sets R and C  */

	lis	4, 0x2000
	ori	4, 4, 0x4008
	lwz	14, 0(4)		/* -> PA 0x0004_3008; sets R only   */

	/* --- translation off; look at the physical side ----------------- */
	mtmsr	11
	lis	4, 0x0004
	ori	4, 4, 0x2010
	lwz	15, 0(4)
	lwz	16, 4(5)		/* first PTE's word 1               */
	lwz	17, 4(6)		/* second PTE's word 1              */

	/* --- an address with no PTE takes the page fault ---------------- */
	mtmsr	12
	lis	0, 0x4600
	ori	0, 0, 0x0D1E
	li	3, 0x2A
	lis	4, 0x2000
	ori	4, 4, 0x5000
	lwz	18, 0(4)		/* -> data access exception         */

	li	19, 0x99		/* must not execute                 */
	HALT(0)
