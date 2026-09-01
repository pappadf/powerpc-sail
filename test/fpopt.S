/* fpopt.S — fsel, fres and stfiwx, the optional floating-point instructions
 * the 603, 604, 604e and 750 all implement and the 601 does not.
 *
 * NOT A 601 TEST: MPC601UM Table 10-6 lists fsel, fres, frsqrte and stfiwx
 * among the instructions that core does not have, and this model decodes them
 * as illegal there (model/ppc_insts_fp.sail).  Listed only in the
 * p603/p604/p604e/p750 manifests.
 *
 * Constants are built in GPRs and stored to 0x4000 rather than assembled into
 * a data section, so that the program stays position-independent and the
 * scratch addresses are visible in the expected state.
 *
 * FSEL frD,frA,frC,frB delivers frC if frA >= 0 and frA is not a NaN, and frB
 * otherwise (MPCFPE32B §4.6.5).  Four cases, chosen to pin the two edges the
 * manual calls out:
 *   frA = +1.0  -> frC = 3.0        (0x4008_0000_0000_0000)
 *   frA = -1.0  -> frB = 7.0        (0x401C_0000_0000_0000)
 *   frA = -0.0  -> frC = 3.0        THE COMPARISON IGNORES THE SIGN OF ZERO,
 *                                   so negative zero selects frC even though
 *                                   its sign bit is set
 *   frA = QNaN  -> frB = 7.0        a NaN is not >= 0
 *
 * FRES frD,frB is a single-precision estimate of 1/frB.  The architecture
 * requires only one part in 256, so an exact reciprocal is a conforming
 * result and is what this model produces (cores/common/ppc32_insts.sail
 * argues why); the two operands here have reciprocals that are exact in
 * single precision, so any conforming implementation that rounds correctly
 * agrees with the value below and the test does not depend on the model's
 * choice being the only allowed one:
 *   fres(2.0) = 0.5     -> 0x3FE0_0000_0000_0000
 *   fres(4.0) = 0.25    -> 0x3FD0_0000_0000_0000
 *
 * STFIWX frS,rA,rB stores the low word of frS with no conversion — the
 * inverse of fctiw (MPCFPE32B §4.6.3).  fctiw of 5.0 leaves 5 in the low
 * word, so storing it and reading it back as an integer must give 5.  Doing
 * it with stfd instead would store the double, whose low word is 0.
 *
 * Only the high halves of the fsel and fres results are checked, because each
 * value's low half is zero and the high half is what distinguishes them.
 *
 * Expected: halt status 0, r20 = 0x40080000 (3.0), r21 = 0x401C0000 (7.0),
 * r22 = 0x40080000 (-0.0 selected frC), r23 = 0x401C0000 (NaN selected frB),
 * r24 = 0x3FE00000 (0.5), r25 = 0x3FD00000 (0.25), r26 = 5.
 */

#include "testlib.h"

/* Store the double (hi,lo) at offset `off` from r9, via r4. */
#define PUTD(hi, lo, off)   \
	lis	4, hi;      \
	ori	4, 4, lo;   \
	stw	4, off(9);  \
	li	4, 0;       \
	stw	4, off+4(9)

	.text
	.globl _start
_start:
	/* --- floating point must be enabled ----------------------------- */
	mfmsr	11
	ori	11, 11, 0x2000		/* MSR[FP] */
	mtmsr	11

	li	9, 0x4000

	PUTD(0x3FF0, 0x0000,  0)	/*  1.0  */
	PUTD(0xBFF0, 0x0000,  8)	/* -1.0  */
	PUTD(0x4008, 0x0000, 16)	/*  3.0  */
	PUTD(0x401C, 0x0000, 24)	/*  7.0  */
	PUTD(0x8000, 0x0000, 32)	/* -0.0  */
	PUTD(0x7FF8, 0x0000, 40)	/* QNaN  */
	PUTD(0x4000, 0x0000, 48)	/*  2.0  */
	PUTD(0x4010, 0x0000, 56)	/*  4.0  */
	PUTD(0x4014, 0x0000, 64)	/*  5.0  */

	lfd	1,  0(9)		/*  1.0 */
	lfd	2,  8(9)		/* -1.0 */
	lfd	3, 16(9)		/*  3.0 = frC */
	lfd	4, 24(9)		/*  7.0 = frB */
	lfd	5, 32(9)		/* -0.0 */
	lfd	6, 40(9)		/* QNaN */

	/* --- fsel: four selections -------------------------------------- */
	fsel	10, 1, 3, 4		/* +1.0 -> 3.0 */
	fsel	11, 2, 3, 4		/* -1.0 -> 7.0 */
	fsel	12, 5, 3, 4		/* -0.0 -> 3.0 */
	fsel	13, 6, 3, 4		/* QNaN -> 7.0 */

	stfd	10, 128(9)
	stfd	11, 136(9)
	stfd	12, 144(9)
	stfd	13, 152(9)
	lwz	20, 128(9)
	lwz	21, 136(9)
	lwz	22, 144(9)
	lwz	23, 152(9)

	/* --- fres: exact reciprocals ------------------------------------ */
	lfd	7, 48(9)		/* 2.0 */
	lfd	8, 56(9)		/* 4.0 */
	fres	14, 7
	fres	15, 8
	stfd	14, 160(9)
	stfd	15, 168(9)
	lwz	24, 160(9)
	lwz	25, 168(9)

	/* --- stfiwx: the low word, unconverted -------------------------- */
	lfd	9, 64(9)		/* 5.0 -- note r9 and f9 are distinct */
	fctiw	16, 9
	li	5, 176
	stfiwx	16, 9, 5		/* EA = r9 + r5 = 0x40B0 */
	lwz	26, 176(9)

	HALT(0)
