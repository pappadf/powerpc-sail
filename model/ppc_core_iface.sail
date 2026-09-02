/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_core_iface.sail — THE CORE INTERFACE
 *
 * This file declares (as `val` signatures) every hook that a concrete core
 * (601, 603, 604, ...) must implement.  The common model code calls only
 * these hooks for core-specific behaviour; the Makefile selects which core
 * directory provides the implementations (see cores/p601/).
 *
 * To add a new core:
 *   1. create model/cores/pNNN/,
 *   2. implement every val declared here (pNNN_core.sail is a good place),
 *   3. add SPRs via `function clause read_spr / write_spr` (ppc_sprs.sail),
 *   4. add core-specific instructions via scattered ast/encdec/execute
 *      clauses (see cores/p601/p601_insts_power.sail for the pattern),
 *   5. list the files in the Makefile under a new CORE value.
 *
 * Keep this interface as small as possible: anything expressible as common
 * PowerPC behaviour belongs in the common model, not here.
 *
 * THE SHARED POST-601 LAYER.  The 601 is the odd one out: the 603e, 604,
 * 604e and 750 all implement the *architected* 32-bit OEA facilities — split
 * IBAT/DBAT arrays with Vs/Vp validity, the time base, MSR[LE]/[ILE] endian
 * control — in exactly the same way as one another.  Rather than have four
 * core directories repeat that, the common implementation of it lives in
 * model/cores/common/ (ppc32_*.sail) and each of those four cores lists it in
 * the Makefile ahead of its own files.  It is NOT part of this interface: a
 * core is free not to use it, as the 601 does not.
 */

$ifndef _PPC_CORE_IFACE
$define _PPC_CORE_IFACE

/* Human-readable core name, e.g. "PowerPC 601" (used in banners/tracing). */
val core_name : unit -> string

/* Value of the PVR (SPR 287) for this core.
 * 601: version 0x0001, revision implementation-defined (MPC601UM §2.3.3.11). */
val core_pvr : unit -> bits(32)

/* The bits the MSR actually implements on this core, as a mask over the whole
 * register.  Reserved bits cannot be changed and always read as zero, so
 * mtmsr and rfi mask every value through this (§2.3.1 on the 601, and the
 * equivalent MSR table on each later core).  The set genuinely differs:
 * the 601 has no POW/ILE/BE/RI/LE and no MSR-based little-endian control at
 * all, the 603e adds TGPR, and the 604e and 750 add PM.  See the Msr bitfield
 * in ppc_regs.sail, which is the union of every core's fields. */
val core_msr_implemented : unit -> word

/* The bits the decrementer implements.  Both the width and the rate are
 * implementation-defined: the 601 has only manual bits 0-24, stepping once
 * per 128 ns oscillator tick (§2.3.3.5), while the later cores implement all
 * 32 bits and step once per four time-base ticks.  Used by set_dec, so that
 * software and the timer cannot disagree about which bits exist. */
val core_dec_implemented : unit -> word

/* Reset all core-specific state (called from the common reset()).
 * Must establish the core's architected reset values, e.g. for the 601:
 * HID0 = 0x8001_0080, MSR[ME]=1, MSR[EP]=1 (MPC601UM §2.7.1, Table 2-11). */
val core_reset : unit -> unit

/* Advance core timers by one "tick" of the model's time base: RTC on the
 * 601, TB on 603/604.  Also responsible for driving DEC and latching a
 * pending decrementer exception.  Called once per executed instruction from
 * step() — the relation of ticks to real time is a model parameter supplied
 * by the core (601: tick_ns, p601_regs.sail). */
val core_tick : unit -> unit

/* Vector offset (within the exception-prefix-selected 1 MB region) for an
 * exception, e.g. E_SystemCall -> 0x00C00.  A core that does not implement
 * the given exception should throw Model_internal_error. */
val core_exception_vector : PPCException -> bits(32)

/* Block address translation.  Given an effective address and access type,
 * return BAT_Hit(physical address, WIM) when an entry covers the address and
 * permits the access, BAT_Violation() when one covers it but the protection
 * mechanism forbids the access, and BAT_Miss() to fall through to
 * segment/page translation.  Only called when translation is enabled and the
 * selected segment register has T=0 — the caller filters both.
 * Entry format and protection scheme differ per core (the 601 keys blocks
 * with Ks/Ku where later cores use Vs/Vp): see cores/p601/p601_mmu.sail. */
val core_bat_translate : (word, MemoryAccess) -> BatResult

/* --- Direct-store (I/O controller interface) segments, SR[T] = 1 --------- */

/* WHERE the T bit is consulted, which is a real architectural difference and
 * not just a difference of behaviour (MPC601UM Figure 6-4 against MPC603EUM
 * Figure 5-6 / MPC750UM Figure 5-6):
 *
 *  - the 601 checks T BEFORE MSR[DT] and IGNORES the BAT array for a segment
 *    with T = 1, so an I/O controller interface access works with data
 *    translation switched off (§6.5.2.2, §6.7.2) — return true;
 *  - every later core checks the BAT array first and reaches the segment
 *    descriptor, and so the T bit, only with translation enabled — return
 *    false.
 *
 * Instruction fetch takes the MSR[IT] check first on every core, so this
 * governs the data path only. */
val core_direct_store_first : unit -> bool

/* What an access to a segment with T = 1 does.  Called only when the core's
 * ordering above says the T bit governs.
 *  - 601: the I/O controller interface (§6.10) — memory-forced for BUID
 *    x'07F', otherwise a two-packet bus transaction this model cannot do;
 *  - 604/604e: the architected direct-store interface, likewise a bus
 *    transaction (MPC604UM §5.5);
 *  - 603e and 750: the facility was REMOVED, and the access faults —
 *    DSI with DSISR[5] for data, ISI with SRR1[3] for a fetch (MPC603EUM
 *    §1.1.1 and Table 4-2; MPC750UM §5.1.1, Table 5-3).
 * Takes the effective address rather than the segment descriptor because
 * SegReg is declared in ppc_regs.sail, which is ordered after this file;
 * rSR(ea[31 .. 28]) recovers it. */
val core_direct_store : (word, MemoryAccess) -> TranslationResult

/* Is this T = 1 segment "memory-forced", i.e. an ordinary memory access that
 * happens to be described by a segment register rather than a page table?
 * Only the 601 has the notion, via BUID x'07F' (§6.10.4); it is what makes a
 * cache control instruction operate normally there instead of no-opping, and
 * what exempts a floating-point access from §5.4.6.1.2's alignment rule.
 * Later cores have no equivalent and return false.  Takes the effective
 * address, for the reason given for core_direct_store above. */
val core_memory_forced_segment : word -> bool

/* Does this core implement the segment descriptor's no-execute bit, SR[N]
 * (manual bit 3 of a T=0 segment register)?  A fetch from a segment with N
 * set takes an instruction access exception with SRR1[3], the same bit a
 * direct-store fetch sets (MPC603EUM Figure 5-6, MPC750UM §5.1.5.2 and
 * Table 5-3).  The 601 has no such bit — manual bits 3-7 of a T=0 segment
 * register are reserved (MPC601UM §6.10) — and returns false, so a program
 * that leaves rubbish there is not faulted for it. */
val core_segment_no_execute : unit -> bool

/* Effective byte order, for instruction fetch and data alike — on both the
 * 601 and the later cores one control selects it for everything, so one hook
 * covers both.  601: HID0[LM]; 603/604: MSR[LE].  Little-endian is
 * address-munging, not byte-swapping (MPC601UM §2.4.3, see le_munge).
 * true = big-endian.  Split this if a core ever selects the two separately. */
val core_bigendian : unit -> bool

/* Does a machine check with MSR[ME] = 0 actually enter the checkstop state?
 * The architecture says yes unconditionally (§5.2.1), but the 601 gates it
 * on HID0: with both the master checkstop enable and the machine-check
 * checkstop enable clear, the exception is taken instead (§5.4.2,
 * Table 2-22).  Returning true = checkstop, false = take the exception. */
val core_checkstop_enabled : unit -> bool

/* Instruction address breakpoint: does fetching this address trip the core's
 * debug compare, so that an exception is taken INSTEAD of executing the
 * instruction?  601: IABR (HID2) against the modes in HID1 (§5.4.12.1,
 * Tables 2-23/2-24); 603e/604/604e/750: IABR[CEA] with IABR[BE] set, plus
 * IABR[TE] against MSR[IT] on the 750.  A core without the facility returns
 * false. */
val core_inst_breakpoint : word -> bool

/* WHICH exception that breakpoint raises.  The 601 has no instruction address
 * breakpoint exception of its own and reports the match as the run-mode
 * exception at 0x02000 (§5.4.12.1); every later core has a dedicated
 * instruction address breakpoint exception at 0x01300.  The two are different
 * exceptions, not one exception at two addresses — the 601's is shared with
 * MSR[SE] tracing and the others' is not — so the core names it rather than
 * common code assuming one and letting the vector table paper over it. */
val core_inst_breakpoint_exception : unit -> PPCException

/* --- Alignment exceptions ------------------------------------------------ */

/* Must a data access with this effective address, width and rule class raise
 * the alignment exception (0x00600) on this core?  Called BEFORE anything
 * else the instruction would do — the manuals are explicit that "the
 * appropriate range check is performed before the instruction begins
 * execution" (MPC601UM §5.4.6.1, MPC603EUM §4.5.6.1) — so an stwcx. whose
 * reservation is clear, which §5.4.3 exempts from every DATA ACCESS
 * exception cause, is still range-checked here.
 *
 * The rule sets are genuinely per-core, not one set with parameters:
 *  - 601 (§5.4.6.1): a 256 MB boundary crossing faults ALWAYS, in every
 *    translation mode; a 4 KB crossing faults under page translation; a
 *    misaligned lmw/stmw/lwarx/stwcx. that crosses nothing is executed
 *    (POWER compatibility / boundedly undefined);
 *  - 603e/604/604e/750 (§4.5.6 in each manual): NO 256 MB rule for
 *    elementary accesses — "the 604 provides hardware support for misaligned
 *    storage accesses" — but a misaligned floating-point access, lmw, stmw,
 *    lwarx, stwcx., eciwx or ecowx faults outright, whatever it crosses.
 * See cores/p601/p601_core.sail and cores/common/ppc32_core.sail. */
val core_alignment_fault : (word, int, AlignRule) -> bool

/* The value the alignment exception leaves in the DAR for this access.
 * Every core stores the computed EA except the 603e, which stores EA + 4
 * when the fault is a misaligned lmw/stmw/lwarx/stwcx. — "that address
 * value +4 is stored into the DAR" (MPC603EUM Table 4-14 and §4.5.6.2). */
val core_alignment_dar : (word, AlignRule) -> word

/* --- FPSCR --------------------------------------------------------------- */

/* The bits this core's FPSCR implements, as a mask in sail bit positions
 * over the whole register.  Writes are filtered through this, so an
 * unimplemented bit always reads as zero and never trips the FX transition
 * rule or the VX summary.  The 601 lacks VXSOFT (manual bit 21) and VXSQRT
 * (22), and its manual bit 29 is reserved (MPC601UM Table 2-1); the later
 * cores implement all three — bit 29 as NI (MPCFPE32B Table 2-4).  Manual
 * bit 20 is architecturally reserved everywhere. */
val core_fpscr_implemented : unit -> word

/* Data address breakpoint: does this data access trip the core's debug
 * compare, so that a data access exception with DSISR[9] is taken instead?
 * Arguments are the effective address, the access width in bytes, and true
 * for a store.  601: DABR (HID5), which compares at double-word granularity
 * and is enabled separately for loads and stores (§2.3.3.13.4, Table 2-26).
 * The compare is on the EFFECTIVE address and is independent of MSR[DT]
 * (§6.1.9).  A core without the facility returns false. */
val core_data_breakpoint : (word, int, bool) -> bool

$endif
