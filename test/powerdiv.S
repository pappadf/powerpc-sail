/* powerdiv.S — the POWER divides div and divs, which return a remainder.
 *
 * Both put the quotient in rD and the remainder in MQ; div's dividend is the
 * 64-bit (rA)||(MQ) while divs's is the 32-bit (rA) (MPC601UM ch. 10 pages).
 * The remainder takes the sign of the dividend, i.e. the division truncates
 * toward zero, which -100/7 = -14 remainder -2 pins.
 *
 * Two overflow cases: -2^31 / -1 is the only one with defined results (rD =
 * -2^31, MQ = 0), and a zero divisor leaves rD and MQ undefined — which under
 * the model's UNDEF policy means untouched, so the two markers survive.
 * Rc=1 describes the REMAINDER, so the divo. below (MQ = 0) must give EQ —
 * plus SO, which is a copy of the XER[SO] that same instruction just set.
 *
 * Expected (hex): r04=64 r05=7 r06=E r07=2 r08=FFFFFF9C r09=FFFFFFF2
 *   r10=FFFFFFFE r11=64 r12=0 r13=E r14=2 r15=0 r16=1 r17=10 r18=10000000
 *   r19=0 r20=80000000 r21=FFFFFFFF r22=FFFFFFFF r23=80000000 r24=0
 *   r25=C0000000 r26=30000000 r27=000005A5 r28=00001234 r29=0 r30=00001234
 *   r31=C0000000, XER = C0000000 (SO|OV), CR = 30000000 (CR0 = EQ|SO).
 */

#include "testlib.h"

	.text
	.machine "601"
	.globl _start
_start:
	/* --- divs: 32-bit dividend, remainder in MQ -------------------- */
	li	4, 100
	li	5, 7
	divs	6, 4, 5			/* 100/7 = 14 remainder 2           */
	mfspr	7, 0
	li	8, -100
	divs	9, 8, 5			/* -14 remainder -2, not -15 rem 5  */
	mfspr	10, 0

	/* --- div: the dividend is (rA)||(MQ) --------------------------- */
	li	11, 100
	mtspr	0, 11			/* MQ = 100                         */
	li	12, 0			/* rA = 0 -> dividend = 100         */
	div	13, 12, 5		/* 14 remainder 2, as above         */
	mfspr	14, 0

	li	15, 0
	mtspr	0, 15			/* MQ = 0                           */
	li	16, 1			/* rA = 1 -> dividend = 2^32        */
	li	17, 16
	div	18, 16, 17		/* 2^32 / 16 = 0x10000000 rem 0     */
	mfspr	19, 0

	/* --- the one overflow with defined results --------------------- */
	li	3, 0
	mtxer	3			/* clear XER incl. the sticky SO    */
	lis	20, 0x8000
	mtspr	0, 20			/* MQ = 0x80000000                  */
	li	21, -1			/* rA = -1 -> dividend = -2^31      */
	li	22, -1
	divo.	23, 21, 22		/* rD = -2^31, MQ = 0, OV set       */
	mfspr	24, 0			/* r24 = 0                          */
	mfxer	25			/* r25 = 0xC0000000 (SO|OV)         */
	mfcr	26			/* EQ|SO: EQ from the remainder     */

	/* --- a zero divisor leaves both results alone ------------------ */
	li	27, 0x5A5		/* marker in rD                     */
	li	28, 0x1234
	mtspr	0, 28			/* marker in MQ                     */
	mtxer	3
	li	29, 0
	divso	27, 4, 29		/* overflow: OV only, no results    */
	mfspr	30, 0			/* r30 = 0x1234, unchanged          */
	mfxer	31			/* r31 = 0xC0000000 (SO|OV)         */

	HALT(0)
