/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc32_regs.sail — registers shared by every post-601 core in this model
 * (603e, 604, 604e, 750).
 *
 * WHY THIS FILE EXISTS.  These four cores all implement the architected
 * 32-bit OEA facilities the 601 predates or does differently: the time base,
 * split instruction and data BAT arrays with the Vs/Vp validity scheme, and
 * the IABR instruction address breakpoint.  Having each core repeat them
 * would be four chances to get the same thing wrong, so they live here and
 * each of the four lists this file in the Makefile ahead of its own.
 *
 * It is NOT part of the core interface (ppc_core_iface.sail) — a core need
 * not use it, and the 601 does not.  Registers that only SOME of the four
 * have (DABR, PIR, HID1, the 603e's software table search registers, the
 * performance monitor, the 750's L2 and thermal registers) stay in the core
 * directory that has them.
 *
 * Reference: MPCFPE32B (the Programming Environments Manual) §2.2, §2.3 and
 * §7.5 for the architected definitions; the per-core manuals for what each
 * implements.  All bitfield comments give the manual's big-endian bit
 * numbers; sail dec index = 31 - manual index (see prelude.sail).
 */

$ifndef _PPC32_REGS
$define _PPC32_REGS

/* --- Time base (TBU/TBL, MPCFPE32B §2.2.1 and §2.3.12) ------------------- */

/* A 64-bit counter that increments monotonically, read as two 32-bit halves.
 * User-level READ-ONLY via mftb / TBR 268-269; supervisor WRITE via mtspr to
 * SPR 284/285 (the dual-numbering is the same shape as the 601's RTC, and for
 * the same reason).  The 601 has no time base at all and mftb is illegal
 * there (MPC601UM §2.6), which is why this is not in ppc_regs.sail.
 *
 * "The TB is a 64-bit register pair whose contents are incremented once every
 * four bus clock cycles" (MPC603EUM §2.1.1; the 750 says the same in its
 * §2.1.1 implementation note, and the 604 in its §2.1.1). */
register TBU : word
register TBL : word

/* MODEL PARAMETER — the instructions-to-time ratio, which no architectural
 * document can supply because it is a property of the implementation and its
 * clock.  Time base ticks attributed to one executed instruction.
 *
 * The default of one tick per instruction is the coarsest self-consistent
 * choice and keeps timer tests short and exact, matching what the 601's
 * tick_ns default does for the RTC (cores/p601/p601_regs.sail).  Real silicon
 * retires several instructions per tick, since a tick is four bus clocks.
 * TODO: make this a --config parameter rather than a register, together with
 * the 601's tick_ns. */
register tb_per_instruction : int

/* --- Block address translation registers (SPRs 528-543) ------------------ */

/* SPLIT arrays, unlike the 601's single unified one: four instruction BAT
 * pairs (IBAT0U-IBAT3U / IBAT0L-IBAT3L, SPRs 528-535) and four data BAT pairs
 * (DBAT0U-DBAT3U / DBAT0L-DBAT3L, SPRs 536-543).  MPCFPE32B §7.5, Table 2-14:
 *
 *   Upper: manual bits 0-14 BEPI | 15-18 reserved | 19-29 BL | 30 Vs | 31 Vp
 *   Lower: manual bits 0-14 BRPN | 15-24 reserved | 25-28 WIMG | 29 reserved
 *                                                             | 30-31 PP
 *
 * Three differences from the 601's format (MPC601UM Figure 6-11), each of
 * which is why the BAT code cannot be shared with it: the validity scheme is
 * Vs/Vp against MSR[PR] rather than the Ks/Ku key feeding the segment
 * protection rules, the valid bits are in the UPPER register rather than the
 * lower, and BL is eleven bits reaching 256 MB where the 601's BSM is six and
 * stops at 8 MB (Table 2-15 against MPC601UM Table 6-12). */
bitfield Ppc32_BatU : word = {
  BEPI : 31 .. 17,
  BL   : 12 .. 2,
  Vs   : 1,
  Vp   : 0
}
bitfield Ppc32_BatL : word = {
  BRPN : 31 .. 17,
  WIMG : 6 .. 3,
  PP   : 1 .. 0
}

register IBATU : vector(4, word)   /* raw values; wrap with Mk_Ppc32_BatU */
register IBATL : vector(4, word)
register DBATU : vector(4, word)
register DBATL : vector(4, word)

/* --- Instruction address breakpoint register (SPR 1010) ------------------ */

/* Implemented by all four cores, with one difference in bit 31:
 *  - CEA (manual bits 0-29): the WORD address compared against the fetch;
 *  - BE  (manual bit 30): breakpoint enable;
 *  - TE  (manual bit 31): translation enable — compared against MSR[IR], so
 *    a breakpoint can be made to fire only with translation on or only with
 *    it off (MPC604UM Table 2-4, MPC750UM Table 2-3).  RESERVED on the 603e,
 *    whose Table 2-8 defines bits 0-29 and 30 only, so that core's
 *    core_inst_breakpoint does not test it.
 *
 * The field is named CEA after the 601's IABR (MPC601UM §2.3.3.13.3); the
 * later manuals leave bits 0-29 unnamed and describe them as "word address to
 * be compared". */
bitfield Ppc32_Iabr : word = {
  CEA : 31 .. 2,
  BE  : 1,
  TE  : 0
}
register IABR : Ppc32_Iabr

/* --- Hardware implementation-dependent register 0 (SPR 1008) ------------- */

/* Every one of the four has a HID0, and every bit any of them defines is a
 * cache, bus, power-management or clocking control with no consequence for
 * the architected state this model computes: cache enables and locks with no
 * cache to enable, checkstop SOURCES for conditions no model can produce,
 * doze/nap/sleep selection, PLL and precharge timing (MPC603EUM Table 2-2,
 * MPC604UM Table 2-3, MPC750UM Table 2-2).
 *
 * Contrast the 601, whose HID0 has three bits that DO change what the machine
 * computes — the two checkstop enables and, above all, LM, which is that
 * core's only little-endian control (cores/p601/p601_regs.sail).  The later
 * cores put endianness in MSR[LE], so nothing is left here to model.
 *
 * So it is a plain word that reads back what was written, rather than a
 * bitfield naming bits nothing reads.  That is a deliberate simplification
 * and not the manuals' behaviour in one respect: each defines its own
 * reserved bits, which a faithful model would hold at zero.
 * TODO: per-core reserved-bit masks, as for the 601's HIDs. */
register HID0 : word

/* --- Harness register ids for the shared post-601 registers -------------- */

/* Ids for harness_note_write (ppc_harness.sail), which reserves 0x80 and up
 * for the core.  This file takes 0x80-0x9F and leaves 0xA0 and up to the core
 * directories, so that a core adding a register never has to renumber what it
 * shares.  None of these is architectural; see ppc_harness.sail for what they
 * are for and c/harness_hooks.h for the C side that has to agree with them.
 *
 * Ids are RESERVED here for HID1, DABR and PIR even though no single core has
 * all three — the 603 has HID1 but no DABR or PIR, the 604 has DABR and PIR
 * but no HID1, the 750 has HID1 and DABR but no PIR.  Reserving one id per
 * register name, rather than letting each core number its own, keeps a single
 * id-to-name table on the C side valid for every core. */
let hw_tbu    : bits(8) = 0x80
let hw_tbl    : bits(8) = 0x81
let hw_hid0   : bits(8) = 0x82
let hw_hid1   : bits(8) = 0x83
let hw_iabr   : bits(8) = 0x84
let hw_dabr   : bits(8) = 0x85
let hw_pir    : bits(8) = 0x86

let hw_ibatu0 : bits(8) = 0x88   /* .. 0x8B */
let hw_ibatl0 : bits(8) = 0x8C   /* .. 0x8F */
let hw_dbatu0 : bits(8) = 0x90   /* .. 0x93 */
let hw_dbatl0 : bits(8) = 0x94   /* .. 0x97 */

/* --- Shared reset of the above ------------------------------------------- */

/* Called from each core's core_reset().  MPCFPE32B §2.3.12.1 leaves the time
 * base undefined at reset and the per-core hard-reset tables (MPC603EUM
 * Table 4-9, MPC750UM Table 4-7) say the BAT registers and HID0 are undefined
 * or zero depending on the core; zeroing everything is the choice this model
 * makes everywhere else for "undefined at reset" and keeps a reset run
 * reproducible. */
val ppc32_reset_regs : unit -> unit
function ppc32_reset_regs() = {
  TBU = zeros(32);
  TBL = zeros(32);
  tb_per_instruction = 1;
  foreach (i from 0 to 3) {
    IBATU[i] = zeros(32);
    IBATL[i] = zeros(32);
    DBATU[i] = zeros(32);
    DBATL[i] = zeros(32)
  };
  IABR = Mk_Ppc32_Iabr(zeros(32));
  HID0 = zeros(32)
}

/* --- Shared timer tick ---------------------------------------------------- */

/* Advance the time base and the decrementer by one instruction's worth of
 * model time.  Called from each core's core_tick().
 *
 * The two counters share a frequency — "the decrementer register is
 * decremented and the time base is incremented at a speed that is one-fourth
 * the speed of the bus clock" (MPC750UM §2.1.1 implementation note; MPC603EUM
 * §1.2.2 says the same of both) — so one step drives both, exactly as the
 * 601's single accumulator drives its RTC and DEC together.
 *
 * TBL carries into TBU on wrapping, which is the whole of the 64-bit counter's
 * behaviour (MPCFPE32B §2.3.12): unlike the 601's RTCL there is no decimal
 * boundary, so the carry is the natural one.
 *
 * set_dec latches the exception request on the 0 -> 1 transition of manual
 * bit 0, the same path an mtspr to the DEC takes (ppc_regs.sail). */
val ppc32_tick : unit -> unit
function ppc32_tick() = {
  let ticks = tb_per_instruction;
  if ticks > 0 then {
    let next_tbl = TBL + ticks;
    harness_wrote(hw_tbl);
    /* Unsigned wrap of the low half is the carry into the high half. */
    if unsigned(next_tbl) < unsigned(TBL) then {
      harness_wrote(hw_tbu);
      TBU = TBU + 1
    };
    TBL = next_tbl;
    set_dec(DEC - ticks)
  }
}

$endif
