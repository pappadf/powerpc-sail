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
 */

$ifndef _PPC_CORE_IFACE
$define _PPC_CORE_IFACE

/* Human-readable core name, e.g. "PowerPC 601" (used in banners/tracing). */
val core_name : unit -> string

/* Value of the PVR (SPR 287) for this core.
 * 601: version 0x0001, revision implementation-defined (MPC601UM §2.3.3.11). */
val core_pvr : unit -> bits(32)

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
 * debug compare, so that a run-mode exception is taken INSTEAD of executing
 * the instruction?  601: IABR (HID2) against the modes in HID1 (§5.4.12.1,
 * Tables 2-23/2-24).  A core without the facility returns false. */
val core_inst_breakpoint : word -> bool

/* Data address breakpoint: does this data access trip the core's debug
 * compare, so that a data access exception with DSISR[9] is taken instead?
 * Arguments are the effective address, the access width in bytes, and true
 * for a store.  601: DABR (HID5), which compares at double-word granularity
 * and is enabled separately for loads and stores (§2.3.3.13.4, Table 2-26).
 * The compare is on the EFFECTIVE address and is independent of MSR[DT]
 * (§6.1.9).  A core without the facility returns false. */
val core_data_breakpoint : (word, int, bool) -> bool

$endif
