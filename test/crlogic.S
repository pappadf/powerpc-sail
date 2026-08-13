/* crlogic.S — the eight CR-logical instructions, full truth table each.
 *
 * cr6 is set to LT by a compare, which gives a 1-bit (CR bit 24, LT) and a
 * 0-bit (CR bit 25, GT) to feed the operations with.  Naming the same bit
 * twice supplies the (1,1) and (0,0) input pairs, so all four combinations
 * come out of those two source bits.
 *
 * Each instruction writes its four results into one CR field, in the order
 *   field bit 0 = op(1,1), 1 = op(1,0), 2 = op(0,1), 3 = op(0,0),
 * so every field of the dumped CR reads as that instruction's truth table:
 *
 *   cr0 crand  1000 = 8      cr4 crnor   0001 = 1
 *   cr1 cror   1110 = E      cr5 creqv   1001 = 9
 *   cr2 crxor  0110 = 6      cr6 crorc   1101 = D
 *   cr3 crnand 0111 = 7      cr7 crandc  0100 = 4
 *
 * crorc goes last because it overwrites cr6, the source field: its four
 * results are written least-significant-bit first so that a source bit is
 * only clobbered once nothing else reads it.
 *
 * Expected: CR = 0x8E6719D4, r10 = 5.
 */

#include "testlib.h"

	.text
	.globl _start
_start:
	li	10, 5
	cmpwi	6, 10, 9		/* cr6 = LT: bit 24 = 1, bit 25 = 0 */

	crand	0, 24, 24		/* cr0 */
	crand	1, 24, 25
	crand	2, 25, 24
	crand	3, 25, 25

	cror	4, 24, 24		/* cr1 */
	cror	5, 24, 25
	cror	6, 25, 24
	cror	7, 25, 25

	crxor	8, 24, 24		/* cr2 */
	crxor	9, 24, 25
	crxor	10, 25, 24
	crxor	11, 25, 25

	crnand	12, 24, 24		/* cr3 */
	crnand	13, 24, 25
	crnand	14, 25, 24
	crnand	15, 25, 25

	crnor	16, 24, 24		/* cr4 */
	crnor	17, 24, 25
	crnor	18, 25, 24
	crnor	19, 25, 25

	creqv	20, 24, 24		/* cr5 */
	creqv	21, 24, 25
	creqv	22, 25, 24
	creqv	23, 25, 25

	crandc	28, 24, 24		/* cr7 */
	crandc	29, 24, 25
	crandc	30, 25, 24
	crandc	31, 25, 25

	crorc	26, 25, 24		/* cr6, in reverse: (0,1) */
	crorc	27, 25, 25		/*                  (0,0) */
	crorc	25, 24, 25		/*  (1,0) — kills the 0 source */
	crorc	24, 24, 24		/*  (1,1) — kills the 1 source */

	HALT(0)
