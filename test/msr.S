/* msr.S — mfmsr, mtmsr and rfi.
 *
 * Three things are checked:
 *
 *  1. mtmsr only changes implemented bits.  Writing 0xFFFF1ACF — every
 *     reserved position set, plus FE0 — leaves 0x00001840, because
 *     reserved MSR bits cannot be changed and read as zero (MPC601UM
 *     §2.3.1, note under Table 2-9).
 *  2. sc followed by rfi returns to the instruction after the sc.  The
 *     handler installed at the system call vector is a single rfi word;
 *     SRR0 already points at the right place, so nothing else is needed.
 *  3. A privileged instruction executed with MSR[PR]=1 takes a program
 *     exception.  That one is last, because reaching the handler halts.
 *
 * Expected: halt status 0x2A, MSR = 0x00001040, SRR1 = 0x00045040
 * (privileged-instruction bit 13 over the user-mode MSR), r04 = 0x1040,
 * r05 = 0xFFFF1ACF, r06 = 0x1840, r07 = 0x5040, r11 = 0x11, r12 = 0x22,
 * r13 = 0 (the trapping mfmsr wrote nothing), r14 = 0.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	mfmsr	4			/* reset value: ME | EP */

	lis	5, 0xFFFF
	ori	5, 5, 0x1ACF
	mtmsr	5
	mfmsr	6			/* only the implemented bits stuck */
	mtmsr	4			/* back to the reset value */

	/* --- sc / rfi round trip ---------------------------------------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0C00		/* system call vector */
	lis	10, 0x4C00
	ori	10, 10, 0x0064		/* the rfi instruction word */
	stw	10, 0(9)

	li	0, 0			/* not the halt magic: a real sc */
	li	11, 0x11
	sc
	li	12, 0x22		/* proves the rfi came back here */

	/* --- privileged instruction in user mode ------------------------ */
	lis	9, 0xFFF0
	ori	9, 9, 0x0700		/* program exception vector */
	lis	10, 0x4400
	ori	10, 10, 0x0002		/* the sc instruction word */
	stw	10, 0(9)

	lis	0, 0x4600
	ori	0, 0, 0x0D1E		/* arm the halt magic */
	li	3, 0x2A			/* status that proves we got there */

	ori	7, 4, 0x4000		/* reset MSR + PR */
	mtmsr	7			/* enter user mode */
	mfmsr	13			/* supervisor-level -> program exception */
	li	14, 0x99		/* must not execute */
	HALT(0)
