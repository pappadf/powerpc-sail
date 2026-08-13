/* illegal.S — the illegal-instruction program exception (MPC601UM §5.4.7,
 * Table 5-16), which is where every opcode the model does not decode ends up.
 *
 * Two words are tried.  The first is all zeros: primary opcode 0 is not
 * assigned, so nothing can decode it.  The second is a real PowerPC
 * instruction that the 601 does not implement — fsqrt (opcode 63, XO 22,
 * Table 10-6) — executed with MSR[FP] set, so that it is the missing
 * instruction rather than a disabled unit that is being tested.  "An illegal
 * instruction program exception is generated when execution of an instruction
 * is attempted with an illegal opcode ... or when execution of an optional
 * instruction not provided in the 601 is attempted" covers both.
 *
 * The handler steps over the faulting word and returns, so the program
 * carries on and both markers land; SRR1[12] is the illegal bit, over an MSR
 * that has FP enabled by the time of the second exception.
 *
 * Expected (hex): r04=00000011 r06=00000022 r07=00083040 (SRR1: illegal, and
 *   MSR[16:31] = 0x3040 with FP set) r30=00000002 (both exceptions taken),
 *   SRR0 = the word after the fsqrt.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- copy the five-instruction handler to the 0x700 vector ----- */
	lis	8, handler@ha
	addi	8, 8, handler@l
	lis	9, 0xFFF0
	ori	9, 9, 0x0700
	li	10, 0
1:	lwzx	11, 8, 10
	stwx	11, 9, 10
	addi	10, 10, 4
	cmpwi	10, 20
	blt	1b

	li	30, 0			/* how many exceptions were taken    */

	/* --- an unassigned primary opcode ------------------------------ */
	.long	0x00000000
	li	4, 0x11			/* reached only by returning         */

	/* --- and an instruction the 601 does not implement ------------- */
	mfmsr	5
	ori	5, 5, 0x2000		/* MSR[FP], so the FPU is available  */
	mtmsr	5
	.long	0xFC00002C		/* fsqrt f0,f0 — 63 | XO 22          */
	li	6, 0x22

	mfspr	7, 27			/* SRR1 from the second exception    */

	HALT(0)

	/* --- the handler: count, step over the word, return ------------ */
handler:
	addi	30, 30, 1
	mfspr	29, 26			/* SRR0 addresses the faulting word  */
	addi	29, 29, 4
	mtspr	26, 29
	rfi
