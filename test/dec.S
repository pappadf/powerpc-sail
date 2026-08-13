/* dec.S — decrementer semantics (§2.3.3.5, §5.4.9).
 *
 * The DEC moves on every instruction, so a test must never record a raw DEC
 * value that depends on where in the program it was read.  Two techniques
 * avoid that:
 *
 *   - read it twice in ADJACENT instructions and record the DIFFERENCE,
 *     which is one tick (128, because the low seven bits of the register do
 *     not exist) wherever the pair sits;
 *   - for the implemented-bits mask, write and read back in adjacent
 *     instructions and subtract the one intervening tick by hand.
 *
 * The exception is checked twice, for the two ways bit 0 can go 0 -> 1:
 *
 *   1. by counting down.  DEC is zero out of reset, so the very first tick
 *      already wrapped it negative and latched a request; MSR[EE] = 0 has
 *      been holding it ever since.  Setting DEC positive does not withdraw
 *      the latched request (only taking the exception does), so enabling
 *      MSR[EE] takes it straight away.
 *   2. by mtspr.  "If the DEC is altered by software and the content of
 *      bit 0 is changed from 0 to 1, an exception request is signaled"
 *      (§2.3.3.5.1) — writing 0x8000_0000 over a positive value does that.
 *
 * The handler counts and returns, so r20 must end at 2.  DEC is left at a
 * large positive value between the two so the countdown cannot fire again
 * on its own.
 *
 * Expected: halt status 0, r7 = 0x80 (one tick between adjacent reads),
 * r8 = 0x00000100 (0x1FF written, masked to 0x180, less one tick),
 * r20 = 2 (both exceptions taken), r21 = 0x11, r22 = 0x22.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- a two-instruction handler at the decrementer vector -------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0900
	lis	10, 0x3A94		/* addi r20,r20,1 = 0x3A940001      */
	ori	10, 10, 0x0001
	stw	10, 0(9)
	lis	10, 0x4C00		/* rfi = 0x4C000064                 */
	ori	10, 10, 0x0064
	stw	10, 4(9)

	/* --- one tick between adjacent reads ---------------------------- */
	mfspr	5, 22
	mfspr	6, 22
	subf	7, 6, 5			/* r5 - r6 = 128                    */

	/* --- the low seven bits are not implemented --------------------- */
	li	4, 0x1FF
	mtspr	22, 4			/* stored as 0x180                  */
	mfspr	8, 22			/* one tick later: 0x100            */

	/* --- park the DEC well away from zero --------------------------- */
	lis	4, 0x4000
	mtspr	22, 4			/* 1 -> 0 on bit 0: no request      */

	/* --- (1) release the request latched by the reset-time wrap ----- */
	mfmsr	11
	ori	12, 11, 0x8000		/* MSR[EE], manual bit 16           */
	mtmsr	12			/* -> decrementer exception         */
	li	21, 0x11

	/* --- (2) drive bit 0 from 0 to 1 by hand ------------------------ */
	lis	4, 0x8000
	mtspr	22, 4			/* -> decrementer exception         */
	li	22, 0x22

	HALT(0)
