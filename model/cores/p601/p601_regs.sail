/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p601_regs.sail — PowerPC 601-specific registers.
 * Reference: MPC601UM §2.2.5 (user), §2.3.3 (supervisor). */

$ifndef _P601_REGS
$define _P601_REGS

/* --- MQ register (SPR 0, §2.2.5.1) — POWER holdover, 601 only ----------- */

/* Read/written by the POWER mul/div and long-shift instructions; left
 * UNDEFINED by mulli/mullw/mulhw/mulhwu/divw/divwu (Tables 2-6/2-7).
 * "Undefined" is modelled as leave-unchanged throughout, which is what lets
 * a test observe that an instruction did not write MQ. */
register MQ : word

/* --- Real-time clock (SPRs 4/5 read, 20/21 write; §2.2.5.3) ------------- */

/* RTCU = seconds (32 bits, all implemented); RTCL = nanoseconds within the
 * current second, of which only manual bits 2-24 exist — the low seven
 * because the least significant implemented bit (24) steps by 128 ns, the
 * top two because a second never needs them.  Unimplemented bits read as
 * zero and a write ignores them (§2.2.5.3.1).
 * The 601 has NO time base; mftb is illegal (§2.6, Table 10-6). */
register RTCU : word
register RTCL : word

let rtcl_implemented : word = 0x3FFFFF80   /* manual bits 2-24 */

/* One tick of the 7.8125 MHz oscillator that drives both the RTC and the
 * decrementer, in nanoseconds: RTCL bit 24 steps by this and DEC bit 24
 * steps down by it (§2.2.5.3.1, §2.3.3.5.1).  Both counters therefore move
 * in units of 128 in their register encodings. */
let rtc_tick_ns : int = 128

/* RTCL counts a whole second and then carries into RTCU: its terminal value
 * is 999,999,872 = one billion minus one tick (§2.2.5.3.1). */
let rtc_second_ns : int = 1000000000

/* MODEL PARAMETER — the instructions-to-time ratio, which no architectural
 * document can supply because it is a property of the implementation and
 * its clock.  Nanoseconds of model time attributed to one executed
 * instruction.
 *
 * The default makes one instruction take exactly one 128 ns oscillator tick.
 * That is the coarsest self-consistent choice and it keeps timer tests
 * short and exact, but it models a very slow machine: the manual's own
 * yardstick is that 128 ns is "finer than the time required to execute 10
 * Add Immediate instructions" (§2.2.5.3.1), so real silicon retires roughly
 * 8-10 instructions per tick.  Lower this to model that; the accumulator in
 * core_tick() carries the remainder, so any value works.
 * TODO: make this a --config parameter rather than a register. */
register tick_ns : int

/* Model time accumulated but not yet delivered to the counters, in
 * nanoseconds.  Not architected state — it is the fractional part of a
 * 128 ns tick and no instruction can observe it. */
register rtc_ns_acc : int

/* --- Block address translation registers (SPRs 528-535, §2.3.3.12) ------ */

/* 601: FOUR UNIFIED BAT pairs (no separate I/D BATs), and the format
 * differs from later 32-bit PowerPC (§6.7.3, Figure 6-11):
 *  - key bits Ks/Ku instead of Vs/Vp,
 *  - valid bit V lives in the LOWER register,
 *  - block sizes 128 KB .. 8 MB only.
 *
 * Upper: manual bits: 0-14 BLPI | 25-27 WIM | 28 Ks | 29 Ku | 30-31 PP
 * Lower: manual bits: 0-14 PBN  | 25 V | 26-31 BSM                      */
bitfield P601_BatU : word = {
  BLPI : 31 .. 17,
  WIM  : 6 .. 4,
  Ks   : 3,
  Ku   : 2,
  PP   : 1 .. 0
}
bitfield P601_BatL : word = {
  PBN : 31 .. 17,
  V   : 6,
  BSM : 5 .. 0   /* 000000=128K ... 111111=8M (Table 6-12); only
                    0,1,3,7,15,31,63 are valid values */
}

register BATU : vector(4, word)   /* raw values; wrap with Mk_P601_BatU */
register BATL : vector(4, word)

/* --- HID registers (§2.3.3.13) — all 601-only --------------------------- */

/* HID0 (SPR 1008): checkstop enables/status + control bits (Table 2-22).
 * Reset = 0x8001_0080 = CE and ES and EIU set.
 * Three bits are broken out; the rest are checkstop *sources* for causes
 * this model has no way to produce (cache and bus parity, sequencer
 * timeouts) and individual enables for them.
 *  - CE (manual bit 0):  master checkstop enable;
 *  - EM (manual bit 16): machine-check checkstop enable, clear at reset;
 *  - LM (manual bit 28): little-endian mode (the 601 has no MSR[LE]).
 * With both CE and EM clear, a machine check is taken even with MSR[ME]
 * clear rather than checkstopping — see core_checkstop_enabled. */
bitfield P601_Hid0 : word = {
  CE : 31,
  EM : 15,
  LM : 3
}
register HID0 : P601_Hid0

/* HID1 (SPR 1009): debug modes (Table 2-23).
 *  - M  (manual bits 1-3): run mode.  010 = limited and 110 = full
 *    instruction address compare differ only in how much of the pipeline
 *    the compare sees, which is invisible here; 111 compares branch targets
 *    only; 100 is HID single-instruction step, distinct from MSR[SE].
 *  - RM (manual bits 8-9): what a compare does.  Only 10, "trap to run mode
 *    exception", is modellable — 00 and 01 stop the clocks. */
bitfield P601_Hid1 : word = {
  M  : 30 .. 28,
  RM : 23 .. 22
}
register HID1 : P601_Hid1

/* HID2 = IABR (SPR 1010): instruction address breakpoint (§2.3.3.13.3).
 * CEA is manual bits 0-29, so the compare ignores the low two bits of the
 * address; manual bits 30-31 are reserved and should be written zero. */
bitfield P601_Iabr : word = {
  CEA : 31 .. 2
}
register IABR : P601_Iabr

/* HID5 = DABR (SPR 1013): data address breakpoint (§2.3.3.13.4, Table 2-25).
 *  - DAB (manual bits 0-28): the DOUBLE-WORD effective address to compare;
 *  - manual bit 29 is reserved but reads back what was written;
 *  - SA (manual bits 30-31): 00 disabled, 01 loads, 10 stores, 11 both. */
bitfield P601_Dabr : word = {
  DAB : 31 .. 3,
  SA  : 1 .. 0
}
register DABR : P601_Dabr

/* HID15 = PIR (SPR 1023): 4-bit processor ID tag (§2.3.3.13.5). */
register PIR : word

$endif
