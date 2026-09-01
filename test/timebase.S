/* timebase.S — the time base and the decrementer on the post-601 cores.
 *
 * NOT A 601 TEST: that core has no time base at all and mftb is illegal on it
 * (MPC601UM §2.6, Table 10-6); its decrementer is a different width driven at
 * a different rate.  Listed only in the p603/p604/p604e/p750 manifests.
 *
 * Three things are checked, each of which is new with these cores:
 *
 * 1. mftb READS THE TIME BASE, and the counter advances by one per completed
 *    instruction.  The rate is the model parameter tb_per_instruction
 *    (cores/common/ppc32_regs.sail), whose default is one tick per
 *    instruction; the architecture fixes only that TB and DEC share a
 *    frequency ("the decrementer register is decremented and the time base is
 *    incremented at a speed that is one-fourth the speed of the bus clock",
 *    MPC750UM §2.1.1), not what an instruction costs.
 *
 *    The tick happens AFTER the instruction completes (core_tick is called at
 *    the end of step, model/ppc_step.sail), so an mtspr that writes TBL = 0
 *    leaves TBL = 1 for the next instruction to read.  Hence:
 *
 *      mtspr 284, r3   TBL <- 0, then tick -> 1
 *      mftb  r4        reads 1, then tick -> 2
 *      mftb  r5        reads 2, then tick -> 3
 *      mftb  r6        reads 3
 *
 *    Expected r4 = 1, r5 = 2, r6 = 3.
 *
 * 2. TBL CARRIES INTO TBU.  TBU is set to 0xFFFF_FFFE as a marker and TBL to
 *    0xFFFF_FFFE; two ticks later TBL has wrapped to zero and TBU has become
 *    0xFFFF_FFFF.  That the marker survives proves TBU is writable through
 *    SPR 285, and that it moved by exactly one proves the carry.
 *
 *      li    r3, -2    tick
 *      mtspr 285, r3   TBU <- 0xFFFFFFFE, tick
 *      li    r3, -2    tick
 *      mtspr 284, r3   TBL <- 0xFFFFFFFE, then tick -> 0xFFFFFFFF
 *      ori   r0, r0, 0 tick -> TBL wraps to 0, TBU -> 0xFFFFFFFF
 *      mftb  r7        reads TBL = 0, tick -> 1
 *      mftbu r8        reads TBU = 0xFFFFFFFF
 *
 *    Expected r7 = 0x00000000, r8 = 0xFFFFFFFF.
 *
 * 3. THE DECREMENTER IS 32 BITS WIDE and steps at the same rate, both of
 *    which differ from the 601.  Writing 100 and reading twice gives 99 then
 *    98 — one per instruction, where the 601 steps by 128.  Writing 0x7F and
 *    reading back gives 0x7E, where the 601 keeps only manual bits 0-24
 *    (dec_implemented = 0xFFFFFF80 there) and would have stored zero.
 *
 *    MSR[EE] is clear out of reset on every one of these cores, so none of
 *    this can take a decrementer exception.
 *
 * Expected: halt status 0, r4 = 1, r5 = 2, r6 = 3, r7 = 0, r8 = 0xFFFFFFFF,
 * r9 = 99 (0x63), r10 = 98 (0x62), r11 = 0x7E.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- 1. mftb, and one tick per instruction ---------------------- */
	li	3, 0
	mtspr	284, 3			/* TBL <- 0                         */
	mftb	4
	mftb	5
	mftb	6

	/* --- 2. the carry from TBL into TBU ----------------------------- */
	li	3, -2
	mtspr	285, 3			/* TBU <- 0xFFFFFFFE                */
	li	3, -2
	mtspr	284, 3			/* TBL <- 0xFFFFFFFE                */
	ori	0, 0, 0			/* one tick: TBL wraps, TBU carries */
	mftb	7
	mftbu	8

	/* --- 3. a 32-bit decrementer at the same rate ------------------- */
	li	3, 100
	mtspr	22, 3			/* DEC <- 100                       */
	mfspr	9, 22
	mfspr	10, 22

	li	3, 0x7F			/* the 601 would keep none of this  */
	mtspr	22, 3
	mfspr	11, 22

	HALT(0)
