/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc32_dabr.sail — the architected data address breakpoint facility, shared
 * by the 604, 604e and 750.  The 603 does NOT have it (the DABR is optional,
 * MPCFPE32B §2.3.14, and MPC603EUM Table 2-40 does not list it), so the
 * Makefile includes this file only for the three cores that do — hence a file
 * of its own rather than a section of ppc32_regs.sail.
 *
 * The whole facility is one register, one SPR clause and one compare, so it
 * is kept together in one file; it sits in the core SPR slot of the build,
 * which is inside the scattered read_spr/write_spr definitions and before
 * anything that calls the compare.
 *
 * Reference: MPCFPE32B §2.3.14 and Table 2-20, which the 604 (Table 2-5) and
 * 750 (§2.1.2.3) both follow.  The 601's DABR is a DIFFERENT register with a
 * different layout and lives in cores/p601/. */

$ifndef _PPC32_DABR
$define _PPC32_DABR

/* DAB (manual bits 0-28) names a DOUBLE WORD; BT selects which translation
 * mode the breakpoint is armed in; DW and DR arm it for stores and loads
 * respectively (Table 2-20). */
bitfield Ppc32_Dabr : word = {
  DAB : 31 .. 3,
  BT  : 2,
  DW  : 1,
  DR  : 0
}
register DABR : Ppc32_Dabr

function clause read_spr(0b1111110101 /* 1013 DABR */) = Some(DABR.bits)
function clause write_spr(0b1111110101, v) = { harness_wrote(hw_dabr); DABR = Mk_Ppc32_Dabr(v); true }

/* "A data address breakpoint match is detected for a load or store
 * instruction if the three following conditions are met FOR ANY BYTE
 * ACCESSED:
 *    EA[0-28] = DABR[DAB]
 *    MSR[DR]  = DABR[BT]
 *    the instruction is a store and DABR[DW] = 1, or the instruction is a
 *    load and DABR[DR] = 1."                              (MPCFPE32B §2.3.14)
 *
 * "For any byte accessed" is why both ends are tested: an access is at most
 * eight bytes wide, so it can straddle at most one double-word boundary and
 * its first and last byte between them cover every double word it touches.
 * The 601 arrives at the same test from its own manual's wording (§2.3.3.13.4)
 * but with a two-bit enable field and no MSR comparison, which is why the two
 * cores do not share this code.
 *
 * The MSR[DR] = DABR[BT] condition is a genuine difference from the 601,
 * whose compare runs whatever the state of MSR[DT] (§6.1.9).  Here a
 * breakpoint armed with BT = 0 does not fire once translation is on.
 *
 * UNDEF (§2.3.14): a match is undefined for a stwcx. whose store is not
 * performed and for a zero-length lswx/stswx.  This model reports the match
 * in the first case, because the compare happens on the address before the
 * reservation is examined, and does not reach the compare at all in the
 * second, because a zero-length transfer performs no access. */
val ppc32_data_breakpoint : (word, int, bool) -> bool
function ppc32_data_breakpoint(ea, width, is_store) = {
  let armed = if is_store then DABR[DW] == 0b1 else DABR[DR] == 0b1;
  let mode_matches = MSR[DT] == DABR[BT];
  let last = ea + (width - 1);
  armed & mode_matches
        & ((ea[31 .. 3] == DABR[DAB]) | (last[31 .. 3] == DABR[DAB]))
}

$endif
