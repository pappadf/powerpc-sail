/* sync.S — the three memory synchronization instructions (MPC601UM
 * Table 3-21).
 *
 * sync, isync and eieio are architectural no-ops in a sequential
 * single-processor model: there is nothing to order, and no cache state to
 * make visible (§3.5.7).  "No-op" is exactly why they need a test — it is
 * indistinguishable from "not implemented" until something executes them, and
 * nothing else in the suite does.  The check is therefore that they decode,
 * complete, and leave the machine alone: a recognizable CR and XER are loaded
 * first and read back afterwards.
 *
 * Expected (hex): r04=12345678 r05=0000001F r06=12345678 r07=0000001F
 *   r08=00000005 r09=00000006 r11=0000000B,
 *   CR = 12345678, XER = 0000001F.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	lis	4, 0x1234
	ori	4, 4, 0x5678
	mtcrf	0xFF, 4			/* every CR field                    */
	li	5, 0x1F
	mtxer	5			/* XER[BC] = 31                      */

	li	8, 5
	sync
	li	9, 6
	isync
	add	11, 8, 9
	eieio

	mfcr	6			/* unchanged                         */
	mfxer	7			/* unchanged                         */

	HALT(0)
