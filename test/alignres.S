/* alignres.S — lwarx/stwcx.: the reservation protocol, and the alignment
 * range check that PRECEDES it.
 *
 * §5.4.3 exempts an stwcx. whose reservation is clear from every DATA
 * ACCESS exception cause — translation, protection, DABR — but the
 * alignment range check is a different, higher-priority exception whose
 * check "is performed before the instruction begins execution" (MPC601UM
 * §5.4.6.1; MPC603EUM §4.5.6.1 says the same), so a reservation-less
 * stwcx. at a faulting EA still traps.
 *
 * The faulting EA is 0x0FFFFFFE: misaligned AND crossing the 256 MB
 * boundary at 0x10000000, so it faults on every core — the 601 for the
 * crossing (§5.4.6.1.1, its misalignment alone being boundedly undefined),
 * the later cores because a misaligned stwcx. faults outright (§4.5.6).
 *
 * DAR: the EA, 0x0FFFFFFE — except the 603e, which stores EA + 4 =
 * 0x10000002 for a misaligned lmw/stmw/lwarx/stwcx. (MPC603EUM Table 4-14
 * and §4.5.6.2).
 *
 * Before the fault, the protocol itself, with XER[SO] = 1 so the CR0 copy
 * is visible:
 *   r14 = 0x10000000   cr0 = 0b0001 after stwcx. with no reservation
 *   r15 = 0x00000077   the word it did not store
 *   r16 = 0x00000077   lwarx result
 *   r17 = 0x30000000   cr0 = 0b0011 after stwcx. with the reservation
 *   r18 = 0x00000123   the word it did store
 *   r20 = 0            the instruction after the fault must not run
 * Halt: status 0x2A at the alignment vector.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- install `sc` at the alignment vector 0xFFF0_0600 --------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0600
	lis	10, 0x4400
	ori	10, 10, 0x0002
	stw	10, 0(9)

	/* --- XER[SO], and a seeded word at 0x4000 --------------------- */
	lis	4, 0x8000
	mtxer	4
	li	11, 0x4000
	li	12, 0x77
	stw	12, 0(11)

	/* --- stwcx. with no reservation: cr0 = 0b0001, no store ------- */
	li	13, 0x123
	stwcx.	13, 0, 11
	mfcr	14			/* 0x10000000                       */
	lwz	15, 0(11)		/* 0x77                             */

	/* --- lwarx / stwcx. pair: cr0 = 0b0011, store performed ------- */
	lwarx	16, 0, 11		/* 0x77, reservation set            */
	stwcx.	13, 0, 11
	mfcr	17			/* 0x30000000                       */
	lwz	18, 0(11)		/* 0x123                            */

	/* --- arm the halt convention, then the faulting stwcx. -------- */
	lis	0, 0x4600
	ori	0, 0, 0x0D1E
	li	3, 0x2A
	lis	19, 0x0FFF
	ori	19, 19, 0xFFFE		/* r19 = 0x0FFFFFFE                 */
	stwcx.	13, 0, 19		/* no reservation; must still trap  */

	li	20, 0x99		/* must not execute                 */
	HALT(0)
