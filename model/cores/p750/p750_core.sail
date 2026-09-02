/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p750_core.sail — PowerPC 750 (G3) implementation of the parts of the core
 * interface not shared with the other post-601 cores;
 * cores/common/ppc32_core.sail supplies the rest.
 * Reference: MPC750UM. */

$ifndef _P750_CORE
$define _P750_CORE

function core_name() = "PowerPC 750"

/* PVR: "the processor version number is 0x0008 for the MPC750.  The processor
 * revision level starts at 0x0100 and is updated for each silicon revision"
 * (§2.1.1 implementation note).  The revision is left at 0x0000 here, as for
 * every other core in this model.
 *
 * Note §6.1's remark that "software can distinguish between the MPC750 and
 * the MPC755 by reading the PVR.  The MPC755 PVR reads as 0x0008_3100" — the
 * two share a version number and differ only in revision, which is why the
 * MPC755's software table search facility is NOT reachable by version alone
 * and is not modelled here (see p750_sprs.sail). */
function core_pvr() = 0x00080000

/* MSR fields the 750 implements (Table 2-5 / §2.1.1): POW ILE EE PR FP ME FE0
 * SE BE FE1 IP IR DR PM RI LE — the 604e's set exactly.  Bit 14 is reserved:
 * the 750 reloads its TLBs in hardware and has no TGPR, unlike the 603. */
function core_msr_implemented() =
  [Mk_Msr(zeros(32)) with POW = 0b1, ILE = 0b1, EE = 0b1, PR = 0b1, FP = 0b1,
                          ME = 0b1, FE0 = 0b1, SE = 0b1, BE = 0b1, FE1 = 0b1,
                          EP = 0b1, IT = 0b1, DT = 0b1, PM = 0b1, RI = 0b1,
                          LE = 0b1].bits

/* Hard reset, Table 2-19 ("Settings Caused by Hard Reset (Used at Power-On)"):
 * MSR = 0x0000_0040, "only IP set" — so, as on the 603, ME comes up CLEAR and
 * a machine check before software sets it goes straight to checkstop.
 * DEC = 0xFFFF_FFFF; HID0, HID1, IABR, ICTC, L2CR, THRM1-THRM3, TBU/TBL, SIA,
 * the MMCRs and the user mirrors all 0x0000_0000; the DABR "breakpoint is
 * disabled, address is undefined"; the PMCs, GPRs, FPRs, CR, CTR, SRs, BATs
 * and TLBs undefined.
 *
 * The undefined ones are zeroed (reset_common_regs and ppc32_reset_regs),
 * which is this model's choice for "undefined at reset" throughout and which
 * satisfies the DABR's "breakpoint is disabled" as a side effect — a zero
 * DABR has DW and DR clear. */
function core_reset() = {
  ppc32_reset_regs();
  DABR = Mk_Ppc32_Dabr(zeros(32));
  HID1 = zeros(32);
  L2CR = zeros(32);
  ICTC = zeros(32);
  THRM1 = zeros(32);
  THRM2 = zeros(32);
  THRM3 = zeros(32);
  MMCR0 = zeros(32);
  MMCR1 = zeros(32);
  PMC1 = zeros(32);
  PMC2 = zeros(32);
  PMC3 = zeros(32);
  PMC4 = zeros(32);
  SIA = zeros(32);
  DEC = 0xFFFFFFFF;
  MSR[EP] = 0b1
}

/* Exception vector offsets, Table 1-5 / §4.5.
 *
 * The 750's set is the 604's plus the 0x01700 thermal management interrupt,
 * which is unique to this core among the four.  Like the 604 it has NO TLB
 * miss vectors — "the MPC750 does not support software table search
 * operations" (§C.4.3) — and no 0x00E00: "the MPC750 does not generate an
 * exception to this vector.  Other processors may use this vector for
 * floating-point assist exceptions."
 *
 * Three of these can never be raised by this model, and each for a reason
 * that belongs to the facility rather than to the table: the performance
 * monitor counters never move and the thermal sensor never reads (see
 * p750_regs.sail), and the system management interrupt has no input signal to
 * assert — the same reason the external interrupt is never raised either,
 * which is a property of having no platform rather than of this core. */
function core_exception_vector(e) =
  match e {
    E_Reset            => 0x00000100,
    E_MachineCheck     => 0x00000200,
    E_DataAccess       => 0x00000300,
    E_InstAccess       => 0x00000400,
    E_External         => 0x00000500,
    E_Alignment        => 0x00000600,
    E_Program          => 0x00000700,
    E_FPUnavailable    => 0x00000800,
    E_Decrementer      => 0x00000900,
    E_SystemCall       => 0x00000C00,
    E_Trace            => 0x00000D00,
    E_PerfMonitor      => 0x00000F00,
    E_InstBreakpoint   => 0x00001300,
    E_SystemManagement => 0x00001400,
    E_Thermal          => 0x00001700,
    _                  => throw(Model_internal_error("exception not implemented on the 750"))
  }

/* Direct-store: NOT SUPPORTED, as on the 603 and unlike the 604.  "The MPC750
 * does not provide support for direct-store segments.  Operations attempting
 * to access a direct-store segment will invoke a DSI exception" (§5.1.1), and
 * Table 5-3 gives both halves — DSI with DSISR[5] for a data access
 * "including floating-point accesses", ISI with SRR1[3] for a fetch.
 *
 * §4.5.3 draws out one consequence worth recording: "in the MPC750, a
 * floating-point load or store to a direct-store segment causes a DSI
 * exception rather than an ALIGNMENT exception, as specified by the PowerPC
 * architecture" — a deliberate deviation of the silicon from the
 * architecture, and this hook produces it, because every access to such a
 * segment arrives here and leaves as Fault_DirectStore whatever its kind.
 * That the model gets it right is a consequence of the 601's §5.4.6.1.2
 * alignment rule being reached only via core_memory_forced_segment, which is
 * false on this core (cores/common/ppc32_core.sail). */
function core_direct_store(_ea, _acc) = TR_Fault(Fault_DirectStore)

/* Instruction address breakpoint (Table 2-3, §4.5.14).  All three conditions:
 * "the instruction breakpoint address IABR[0-29] matches EA[0-29] of the next
 * instruction to complete in program order ... the translation enable bit
 * (IABR[TE]) matches MSR[IR] ... the breakpoint enable bit (IABR[BE]) is
 * set."  §4.5.14 is explicit that "the instruction that triggers the
 * instruction address breakpoint exception is not executed before the
 * exception handler is invoked", which is what step() does. */
function core_inst_breakpoint(cia) =
  (IABR[BE] == 0b1)
  & (IABR[TE] == MSR[IT])
  & (cia[31 .. 2] == IABR[CEA])

function core_data_breakpoint(ea, width, is_store) =
  ppc32_data_breakpoint(ea, width, is_store)


/* Alignment (§4.5.6): as the 604 but WITHOUT the floating-point
 * direct-store alignment fault — "in the MPC750, a floating-point load or
 * store to a direct-store segment causes a DSI exception rather than an
 * alignment exception, as specified by the PowerPC architecture" (§4.5.6),
 * and core_direct_store above already produces that DSI.  The string
 * boundary sentence appears in this manual too (ch. 2, load/store string
 * section). */
function core_alignment_fault(ea, n, rule) =
  ppc32_alignment_fault(false, true, false, ea, n, rule)

function core_alignment_dar(ea, _rule) = ea

$endif
