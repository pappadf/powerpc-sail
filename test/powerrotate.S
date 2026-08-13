/* powerrotate.S — the POWER rotate/mask holdovers rlmi, rrib, maskg, maskir.
 *
 * rlmi is rlwimi with the rotate amount in a register; rrib inserts a single
 * bit; maskg generates the mask that maskir then merges under.  All four are
 * 601-only (MPC601UM Table 3-8), hence `.machine "601"`.
 *
 * maskg is checked in all three of the cases its ch. 10 page lists —
 * mstart <= mstop, mstart > mstop + 1 (the run of ones wraps round bit 31),
 * and mstart = mstop + 1 (every bit set) — because they are what identify it
 * with the architecture's own MASK(MB, ME).
 *
 * Expected (hex): r04=12345678 r05=AAAAAAAA r06=AA56AAAA r07=8 r08=AA56AAAA
 *   r09=00000108 r10=04000000 r11=80000000 r12=5 r13=FBFFFFFF r14=7FFFFFFF
 *   r15=4 r16=B r17=0FF00000 r18=F81FFFFF r19=C r20=FFFFFFFF r21=7
 *   r22=01000000 r23=AAAA5678 r24=0000FFFF r25=80000000,
 *   XER = 0, CR = 80000000 (CR0 = LT from the final maskir.).
 */

#include "testlib.h"

	.text
	.machine "601"
	.globl _start
_start:
	lis	4, 0x1234
	ori	4, 4, 0x5678		/* r4 = 0x12345678                  */
	lis	5, 0xAAAA
	ori	5, 5, 0xAAAA		/* r5 = 0xAAAAAAAA                  */

	/* --- rlmi: ROTL(rS, rB) inserted into rA under MASK(MB, ME) ---- */
	mr	6, 5
	li	7, 8
	rlmi	6, 4, 7, 8, 15		/* ROTL = 0x34567812, mask 00FF0000 */
	mr	8, 5
	li	9, 0x108		/* only rB[27:31] is the amount     */
	rlmi.	8, 4, 9, 8, 15		/* same answer; CR0 = LT            */
	mfcr	25			/* r25 = 0x80000000                 */

	/* --- rrib: bit 0 of rS inserted at bit rB[27:31] of rA --------- */
	li	10, 0
	lis	11, 0x8000		/* r11 bit 0 = 1                    */
	li	12, 5
	rrib	10, 11, 12		/* set bit 5 -> 0x04000000          */
	li	13, -1
	lis	14, 0x7FFF
	ori	14, 14, 0xFFFF		/* r14 bit 0 = 0                    */
	rrib	13, 14, 12		/* clear bit 5 -> 0xFBFFFFFF        */

	/* --- maskg: ones from rS[27:31] through rB[27:31] -------------- */
	li	15, 4
	li	16, 11
	maskg	17, 15, 16		/* 4 <= 11: bits 4-11               */
	maskg	18, 16, 15		/* 11 > 5: zeros only at bits 5-10  */
	li	19, 12
	maskg	20, 19, 16		/* mstart = mstop + 1: all ones     */
	li	21, 7
	maskg	22, 21, 21		/* a single bit                     */

	/* --- maskir: rS merged into rA under the mask in rB ------------ */
	mr	23, 5
	li	24, 0
	ori	24, 24, 0xFFFF		/* r24 = 0x0000FFFF                 */
	maskir.	23, 4, 24		/* low half from r4, high from r5   */

	HALT(0)
