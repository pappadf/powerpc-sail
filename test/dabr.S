/* dabr.S — the data address breakpoint (§2.3.3.13.4, Tables 2-25/2-26).
 *
 * DABR (HID5) watches ONE double word, named by manual bits 0-28, and the
 * SA field in manual bits 30-31 enables the compare per direction: 00 off,
 * 01 loads, 10 stores, 11 both.  A match is a data access exception with
 * DSISR[9] set, and the access itself is inhibited.
 *
 * The value used here is 0x0000_4001: the double word at 0x4000, loads only.
 * Three things follow, and the program checks each:
 *
 *   - a STORE to 0x4000 is not watched, so it goes through (r6 reads back
 *     what it wrote, once the breakpoint is out of the way);
 *   - a load from 0x4008 is a different double word, so it is not a match;
 *   - a load of the WORD at 0x3FFE straddles the boundary — its first byte
 *     is in the double word at 0x3FF8 and its last in the one at 0x4000 —
 *     and Table 2-26 says "if any part of the load access touches the
 *     double word specified in the DABR ... the DAE occurs".
 *
 * Writing SA = 00 in the middle also exercises the disabled case, which is
 * the only way to read the watched location back.
 *
 * Expected: halt status 0x2A, CIA = 0xFFF00300, DAR = 0x00003FFE,
 * DSISR = 0x00400000 (manual bit 9 alone; bit 6 stays clear for a load),
 * r5 = 0 (unwatched load of an untouched location), r6 = 0xA5A5A5A5 (the
 * store was allowed), r7 = 0 (the matching load was inhibited), r11 = 0.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	/* --- install `sc` at the data access exception vector ----------- */
	lis	9, 0xFFF0
	ori	9, 9, 0x0300
	lis	10, 0x4400
	ori	10, 10, 0x0002
	stw	10, 0(9)

	/* --- watch the double word at 0x4000, loads only ---------------- */
	li	4, 0x4001
	mtspr	1013, 4			/* HID5 = DABR                      */

	/* --- a store to the watched double word is not a match ---------- */
	li	8, 0x4000
	lis	4, 0xA5A5
	ori	4, 4, 0xA5A5
	stw	4, 0(8)

	/* --- a load from the next double word is not a match ------------ */
	lwz	5, 8(8)

	/* --- SA = 00 disables the compare; read the store back ---------- */
	li	4, 0
	mtspr	1013, 4
	lwz	6, 0(8)

	/* --- re-enable, then straddle the boundary ---------------------- */
	li	4, 0x4001
	mtspr	1013, 4

	lis	0, 0x4600
	ori	0, 0, 0x0D1E		/* arm the halt magic               */
	li	3, 0x2A
	li	10, 0x3FFE
	lwz	7, 0(10)		/* 0x3FFE..0x4001 -> match          */

	li	11, 0x99		/* must not execute                 */
	HALT(0)
