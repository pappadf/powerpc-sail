/* cacheops.S — the cache instructions that have nothing to act on
 * (§3.8.1, §3.8.2, §4.8).
 *
 * With no cache modelled, what separates these instructions is not what they
 * do but what they still CHECK, so the test turns data translation on with
 * no mappings at all — every data address then page-faults — and sorts them
 * into the two groups:
 *
 *   never fault   dcbt, dcbtst (§4.8.2: "executing dcbt does not cause any
 *                 exceptions to be invoked", and a translation fault or
 *                 protection violation makes them a no-op) and icbi (the
 *                 ch. 10 page: a no-op on the 601 "even to the extent of not
 *                 validating the EA");
 *   still fault   dcbf and dcbst, which "operate as a load from the
 *                 addressed byte with respect to address translation and
 *                 protection", and dcbi, which operates as a STORE — the
 *                 DSISR it leaves behind has manual bit 6 set where the
 *                 other two would leave it clear.
 *
 * dcbi is also supervisor-level, so it appears twice: once in supervisor
 * mode for the store-typed fault and once in user mode for the privileged
 * instruction program exception.
 *
 * To take five exceptions in one program the handler cannot halt.  A
 * four-instruction handler that advances SRR0 past the faulting instruction
 * and returns is copied to both the data access and program exception
 * vectors; copying it (rather than hand-assembling the words) keeps it
 * readable and lets the assembler check it.
 *
 * Expected: halt status 0, DAR = 0x00004000 and DSISR = 0x42000000 — manual
 * bit 1 (page fault) plus bit 6 (store), left by the supervisor-mode dcbi,
 * the last data access exception of the five.  SRR1 = 0x00045050 records the
 * final exception instead: manual bit 13, privileged instruction, over an
 * MSR[16:31] of 0x5050 — ME, EP, PR and DT.
 * r14 = 0x55, r15 = 0x66, r16 = 0x77, r17 = 0x88.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- copy the resume handler to the DSI and program vectors ----- */
	lis	8, handler@ha
	addi	8, 8, handler@l
	lis	9, 0xFFF0
	ori	9, 9, 0x0300
	lis	10, 0xFFF0
	ori	10, 10, 0x0700
	li	7, 0
1:	lwzx	6, 7, 8
	stwx	6, 7, 9
	stwx	6, 7, 10
	addi	7, 7, 4
	cmpwi	7, 16
	blt	1b
	b	begin

	/* SRR0 += 4; rfi — resume after the instruction that faulted. */
handler:
	mfspr	20, 26
	addi	20, 20, 4
	mtspr	26, 20
	rfi

begin:
	/* --- data translation on, nothing mapped ------------------------ */
	mfmsr	11
	ori	12, 11, 0x0010		/* MSR[DT] */
	mtmsr	12

	li	4, 0x4000

	/* --- these must not fault --------------------------------------- */
	dcbt	0, 4
	dcbtst	0, 4
	icbi	0, 4
	li	14, 0x55

	/* --- these fault as loads --------------------------------------- */
	dcbf	0, 4
	dcbst	0, 4
	li	15, 0x66

	/* --- dcbi faults as a store (DSISR manual bit 6) ---------------- */
	dcbi	0, 4
	li	16, 0x77

	/* --- and is privileged ------------------------------------------ */
	mfmsr	12
	ori	12, 12, 0x4000		/* MSR[PR] */
	mtmsr	12
	dcbi	0, 4			/* -> privileged program exception  */
	li	17, 0x88

	HALT(0)
