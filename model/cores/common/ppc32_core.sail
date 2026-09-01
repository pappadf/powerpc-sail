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
 * the 601 faults on a narrower set (§5.4.6.3).
 * TODO: that per-core alignment rule is not yet modelled; the 601's rules in
 * alignment_fault (ppc_mem.sail) are applied on every core. */
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

$endif
