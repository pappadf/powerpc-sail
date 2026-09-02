/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc32_core.sail — the core-interface hooks whose implementation is the SAME
 * on the 603e, 604, 604e and 750.  A core directory implements the rest:
 * core_name, core_pvr, core_msr_implemented, core_reset,
 * core_exception_vector, core_direct_store, core_inst_breakpoint and
 * core_data_breakpoint, each of which genuinely differs between the four.
 *
 * Ordered after the core's own files in the Makefile, so a core's reset can
 * call ppc32_reset_regs() and its core_tick can be this one. */

$ifndef _PPC32_CORE
$define _PPC32_CORE

/* The whole 32-bit register is implemented, unlike the 601's 25 bits: "the
 * decrementer register (DEC) is a 32-bit decrementing counter" (MPC750UM
 * Table 1-2; MPC603EUM §2.1.1 and MPC604UM §2.1.1 say the same), and the
 * exception is signalled when bit 0 goes from 0 to 1, which set_dec latches
 * (ppc_regs.sail). */
function core_dec_implemented() = 0xFFFFFFFF

/* Advance the time base and the decrementer.  Both counters and the reasoning
 * about their shared frequency are in ppc32_regs.sail. */
function core_tick() = ppc32_tick()

/* --- Direct-store ordering ----------------------------------------------- */

/* The architected order: the BAT array is consulted first and the segment
 * descriptor — and so the T bit — is reached only after it misses, and only
 * with translation enabled (MPCFPE32B Figure 7-3; MPC603EUM Figure 5-6;
 * MPC750UM Figure 5-6).  Only the 601 inverts this. */
function core_direct_store_first() = false

/* No later core has the 601's memory-forced encoding: a T=1 segment is a
 * direct-store segment and nothing else. */
function core_memory_forced_segment(_ea) = false

/* All four implement the segment descriptor's no-execute bit (MPCFPE32B
 * §7.6.2.1.1; MPC750UM Table 5-3 lists the resulting ISI explicitly). */
function core_segment_no_execute() = true

/* --- Endianness ---------------------------------------------------------- */

/* MSR[LE] selects little-endian mode for fetch and data alike, and MSR[ILE]
 * supplies the value an exception establishes (take_exception, in
 * ppc_exceptions.sail, does that copy).  This is the architected mechanism
 * the 601 predates — that core has no MSR[LE] and uses HID0[LM] instead.
 *
 * Little-endian is address-munging here just as it is on the 601, so nothing
 * below le_munge (ppc_mem.sail) changes: "the processor ... modifies the
 * three low-order bits of the effective address" (MPCFPE32B §3.1.2.2).
 * NOTE the 603e qualifies which accesses are legal in the mode rather than
 * what they mean — a misaligned single-register access and every multiple or
 * string instruction take an alignment exception (MPC603EUM Table 4-2), where
 * the 601 faults on a narrower set (§5.4.6.3).  That rule lives in
 * ppc32_alignment_fault below. */
function core_bigendian() = MSR[LE] == 0b0

/* --- Machine check -------------------------------------------------------- */

/* Unconditional, unlike the 601: "if MSR[ME] is cleared, the processor enters
 * the checkstop state" (MPC604UM Table 1-2; MPC603EUM §4.5.2 and MPC750UM
 * Table 1-5 agree).  The 601's HID0 escape hatch, which lets the exception be
 * taken with ME clear when both checkstop enables are off, has no equivalent
 * on any of these cores. */
function core_checkstop_enabled() = true

/* --- Instruction address breakpoint --------------------------------------- */

/* All four have a dedicated instruction address breakpoint exception at
 * 0x01300, rather than folding the match into a run-mode exception as the
 * 601 does. */
function core_inst_breakpoint_exception() = E_InstBreakpoint

/* --- Alignment exceptions (§4.5.6 in each manual) ------------------------ */

/* The architected 32-bit rules, which are DISJOINT from the 601's: none of
 * these cores has its blanket 256 MB rule — "the 604 provides hardware
 * support for misaligned storage accesses for other memory access
 * instructions" (MPC604UM §4.5.6; MPC603EUM Table 4-15 lists page-address
 * translation as the ONLY access type with a boundary rule, and MPC750UM
 * §4.5.6 lists no boundary rule at all) — but all of them fault accesses
 * the 601 executes.  Common to the four (each core's §4.5.6 bullet list):
 *
 *  - a floating-point load or store that is not WORD-aligned (word, not
 *    natural: a double on a 4-byte boundary is legal);
 *  - an lmw, stmw, lwarx or stwcx. that is not word-aligned;
 *  - an eciwx or ecowx that is not word-aligned;
 *  - in little-endian mode, any access that is not naturally aligned, and
 *    every multiple or string instruction outright.  (MPC750UM's §4.5.6
 *    omits the misaligned-single-access bullet the other three state; the
 *    PEM's little-endian chapter requires it, so the omission is read as
 *    editorial rather than as hardware that silently munges a misaligned
 *    EA.)
 *
 * The three ways the four cores differ arrive as flags from each core's
 * one-line core_alignment_fault:
 *
 *  `page_4k`  (603e only) — MPC603EUM Table 4-15: under page-address
 *      translation (MSR[DR]=1, SR[T]=0) an elementary operand that crosses
 *      a 4 KB boundary faults, before the instruction begins.  The 604 and
 *      750 instead split the access and let the second page's translation
 *      succeed or DSI on its own (MPC604UM §4.5.6).
 *  `string_boundaries`  (604/604e/750) — "a non-word-aligned string
 *      operation that crosses a 4-Kbyte boundary, or a word-aligned string
 *      operation that crosses a 256-Mbyte boundary always causes an
 *      alignment exception" (MPC604UM §3.x load/store string, MPC604EUM and
 *      MPC750UM same sentence).  The MPC603EUM carries no such sentence and
 *      its §4.5.6 list has no big-endian string rule, so the 603e gets
 *      false.
 *  `fp_direct_store`  (603e/604/604e) — a floating-point load or store to a
 *      direct-store segment faults (MPC603EUM §4.5.6 bullet; the
 *      architected rule, MPCFPE32B §6.4.3).  The 750 is the documented
 *      exception: "a floating-point load or store to a direct-store segment
 *      causes a DSI exception rather than an alignment exception"
 *      (MPC750UM §4.5.6), which core_direct_store already produces.  The
 *      T bit is only reachable with data translation on for these cores
 *      (core_direct_store_first above), hence the MSR[DT] guard. */
val ppc32_alignment_fault : (bool, bool, bool, word, int, AlignRule) -> bool
function ppc32_alignment_fault(page_4k, string_boundaries, fp_direct_store,
                               ea, n, rule) = {
  let word_misaligned = ea[1 .. 0] != 0b00;
  let word_rule : bool = match rule {
    Align_fp       => word_misaligned,
    Align_multiple => word_misaligned,
    Align_atomic   => word_misaligned,
    Align_ext      => word_misaligned,
    _              => false
  };
  let string_rule : bool = match rule {
    Align_string =>
      string_boundaries
      & (   (word_misaligned & crosses_4k(ea, n))
          | (not_bool(word_misaligned) & crosses_256m(ea, n))),
    _ => false
  };
  let page_mode = (MSR[DT] == 0b1) & (rSR(ea[31 .. 28])[T] == 0b0);
  let page_rule : bool = match rule {
    Align_operand => page_4k & page_mode & crosses_4k(ea, n),
    Align_fp      => page_4k & page_mode & crosses_4k(ea, n),
    _             => false
  };
  let misaligned : bool = match rule {
    Align_operand => (n > 1) & (tmod_int(unsigned(ea), n) != 0),
    Align_fp      => (n > 1) & (tmod_int(unsigned(ea), n) != 0),
    Align_atomic  => word_misaligned,
    Align_ext     => word_misaligned,
    _             => true      /* a string or multiple always faults in LE */
  };
  let le_fault = not_bool(core_bigendian()) & misaligned;
  let ds_fault : bool = match rule {
    Align_fp => fp_direct_store & (MSR[DT] == 0b1)
                & (rSR(ea[31 .. 28])[T] == 0b1),
    _        => false
  };
  word_rule | string_rule | page_rule | le_fault | ds_fault
}

/* --- FPSCR ---------------------------------------------------------------- */

/* All four implement the architected register in full (MPCFPE32B Table 2-4):
 * VXSOFT (manual bit 21), VXSQRT (22) and NI (29), which the 601 lacks, are
 * present, and only the architecturally reserved bit 20 is not — sail bit
 * 11.  NI's non-IEEE mode semantics are not modelled; the bit is state. */
function core_fpscr_implemented() = 0xFFFFF7FF

$endif
