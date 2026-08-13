/* powermul.S — the POWER multiply, which keeps the whole 64-bit product.
 *
 * mul rD,rA,rB places the HIGH-order word of the product in rD and the low
 * word in MQ (MPC601UM ch. 10 mulx page), so every case here reads MQ back
 * with mfspr from SPR 0.  Two things are easy to get backwards and are pinned
 * deliberately: which half lands in rD, and the fact that Rc=1 sets CR0 from
 * the MQ half — the mulo. below leaves rD = 1 (which would be GT) and MQ = 0,
 * and CR0 must read EQ — plus SO, which is a copy of the XER[SO] this same
 * instruction has just set.
 *
 * Expected (hex): r04=00010002 r05=00030004 r06=3 r07=000A0008 r08=FFFFFFFE
 *   r09=3 r10=FFFFFFFF r11=FFFFFFFA r12=40000000 r13=4 r14=1 r15=0
 *   r16=C0000000 r17=30000000, XER = C0000000 (SO|OV), CR = 30000000.
 */

#include "testlib.h"

	.text
	.machine "601"
	.globl _start
_start:
	/* --- 0x00010002 * 0x00030004 = 0x0000_0003_000A_0008 ----------- */
	lis	4, 0x0001
	ori	4, 4, 0x0002
	lis	5, 0x0003
	ori	5, 5, 0x0004
	mul	6, 4, 5			/* r6 = high word = 3               */
	mfspr	7, 0			/* MQ = low word  = 0x000A0008      */

	/* --- the operands are signed: -2 * 3 = -6 ---------------------- */
	li	8, -2
	li	9, 3
	mul	10, 8, 9		/* r10 = 0xFFFFFFFF                 */
	mfspr	11, 0			/* MQ  = 0xFFFFFFFA                 */

	/* --- OV means "does not fit in 32 bits", as for mullw ---------- */
	li	3, 0
	mtxer	3			/* clear XER incl. the sticky SO    */
	lis	12, 0x4000		/* r12 = 0x40000000                 */
	li	13, 4
	mulo.	14, 12, 13		/* 0x1_0000_0000: r14 = 1, MQ = 0   */
	mfspr	15, 0			/* r15 = 0                          */
	mfxer	16			/* r16 = 0xC0000000 (SO|OV)         */
	mfcr	17			/* EQ|SO from MQ, not GT from rD    */

	HALT(0)
