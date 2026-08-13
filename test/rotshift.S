/* rotshift.S — the integer rotate and shift instructions.
 *
 * Covers the mask generator including the wrap-around case (MB > ME), the
 * rotate-register form ignoring everything above rB[27:31], mask insertion,
 * the "shift amount >= 32" case of slw/srw/sraw, and every XER[CA] rule of
 * the algebraic right shifts (bits lost from a negative value set it; a
 * positive source or a zero shift clears it).
 *
 * Expected (hex): r04=12345678 r05=34567812 r06=00000078 r07=20000001
 *   r08=00123456 r09=C r10=45678123 r11=2C r12=45678123 r13=FF56FFFF r14=4
 *   r15=23456780 r16=01234567 r17=20 r18=0 r19=0 r20=F2345678 r21=FF234567
 *   r22=20000000 r23=01234567 r24=0 r25=F2345678 r26=0 r27=20 r28=FFFFFFFF
 *   r29=20000000 r30=FF234567 r31=20000000,
 *   XER = 20000000 (CA), CR = 80000000 (CR0 = LT).
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	lis	4, 0x1234
	ori	4, 4, 0x5678		/* r4 = 0x12345678                */

	/* --- rlwinm: rotate, extract, wrap-around mask, shift ----------- */
	rlwinm	5, 4, 8, 0, 31		/* mask of all ones: pure rotate  */
	rlwinm	6, 4, 0, 24, 31		/* extract the low byte           */
	rlwinm	7, 4, 4, 28, 3		/* MB > ME: the mask wraps        */
	rlwinm	8, 4, 24, 8, 31		/* the srwi 8 idiom               */

	/* --- rlwnm: the amount is rB[27:31], nothing above it ----------- */
	li	9, 12
	rlwnm	10, 4, 9, 0, 31
	li	11, 44			/* 44 and 12 differ above bit 27  */
	rlwnm	12, 4, 11, 0, 31	/* ... so this matches r10        */

	/* --- rlwimi: insert under the mask, leave the rest of rA -------- */
	li	13, -1			/* r13 = 0xFFFFFFFF               */
	rlwimi	13, 4, 8, 8, 15

	/* --- slw/srw, including a count of 32 --------------------------- */
	li	14, 4
	slw	15, 4, 14
	srw	16, 4, 14
	li	17, 32
	slw	18, 4, 17		/* rB[26] set -> result is zero   */
	srw	19, 4, 17

	/* --- sraw/srawi and the XER[CA] rules --------------------------- */
	lis	20, 0xF234
	ori	20, 20, 0x5678		/* r20 = 0xF2345678, negative     */
	li	3, 0
	mtxer	3
	sraw	21, 20, 14		/* negative, 1-bits lost -> CA    */
	mfxer	22
	mtxer	3
	srawi	23, 4, 4		/* positive source -> CA clear    */
	mfxer	24
	mtxer	3
	srawi	25, 20, 0		/* a zero shift clears CA         */
	mfxer	26
	mtxer	3
	li	27, 32
	sraw	28, 20, 27		/* fill with sign bits, CA set    */
	mfxer	29
	mtxer	3
	srawi.	30, 20, 4		/* CR0 = LT, and CA set           */
	mfxer	31

	HALT(0)
