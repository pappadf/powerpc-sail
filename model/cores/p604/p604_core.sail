/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p604_core.sail — PowerPC 604 implementation of the parts of the core
 * interface (ppc_core_iface.sail) that are not shared with the other post-601
 * cores; cores/common/ppc32_core.sail supplies the rest.
 * Reference: MPC604UM. */

$ifndef _P604_CORE
$define _P604_CORE

function core_name() = "PowerPC 604"

/* PVR: "the processor version number is 4 for the 604.  The processor
 * revision level starts at 0x0000" (§2.1.1 implementation note). */
function core_pvr() = 0x00040000

/* MSR fields the 604 implements (Table 4-3): POW ILE EE PR FP ME FE0 SE BE
 * FE1 IP IR DR PM RI LE.
 *
 * Two differences from the 603: bit 14 is reserved here rather than TGPR —
 * the 604 reloads its TLBs in hardware and has no need of the temporary GPRs
 * — and bit 29 is PM, "specific to the 604, and defined as reserved by the
 * PowerPC architecture", which the 603 lacks. */
function core_msr_implemented() =
  [Mk_Msr(zeros(32)) with POW = 0b1, ILE = 0b1, EE = 0b1, PR = 0b1, FP = 0b1,
                          ME = 0b1, FE0 = 0b1, SE = 0b1, BE = 0b1, FE1 = 0b1,
                          EP = 0b1, IT = 0b1, DT = 0b1, PM = 0b1, RI = 0b1,
                          LE = 0b1].bits

/* Hard reset.  The 604 manual has no equivalent of the 603's Table 4-9 or the
 * 750's Table 2-19 — it describes the HRESET signal (§7.2.9.6.1) and the
 * system reset exception (§4.5.1) without tabulating the resulting register
 * values.  What §4.5.1 does fix is that the exception is taken with MSR[IP]
 * set, which is what makes the first fetch come from 0xFFF0_0100.
 *
 * So the state below is the 603's and 750's, which agree with each other
 * exactly (MSR = 0x0000_0040, DEC = 0xFFFF_FFFF, the implementation-specific
 * registers cleared) and which the 604 sits between in time.  That is an
 * inference, not a transcription, and it is the only one in this file.
 * TODO-VERIFY: the reset values of PIR and the performance monitor registers
 * on real 604 silicon. */
function core_reset() = {
  ppc32_reset_regs();
  DABR = Mk_Ppc32_Dabr(zeros(32));
  PIR = zeros(32);
  MMCR0 = zeros(32);
  PMC1 = zeros(32);
  PMC2 = zeros(32);
  SIA = zeros(32);
  SDA = zeros(32);
  DEC = 0xFFFFFFFF;
  MSR[EP] = 0b1
}

/* Exception vector offsets, Table 1-2 / §4.5.
 *
 * The 604 has the 0x00F00 performance monitor interrupt the 603 lacks, and
 * has none of the three TLB miss vectors — it reloads its TLBs in hardware,
 * so those offsets are simply reserved (Table 1-2: "Reserved 01000-012FF").
 *
 * NOT implemented, and so absent: 0x00E00 floating-point assist, which
 * Table 1-2 marks "defined by the PowerPC architecture, but not required in
 * the 604".  An E_FPAssist here would be a model error, hence the throw.
 *
 * The performance monitor interrupt is listed although nothing can raise it —
 * the counters never move (see p604_regs.sail) — for the same reason the 603
 * lists its TLB miss vectors: the table documents where the core puts each
 * exception, and reachability is a property of the facility, not of this
 * table. */
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
    _                  => throw(Model_internal_error("exception not implemented on the 604"))
  }

/* Direct-store: the 604 STILL IMPLEMENTS the facility, unlike the 603 and the
 * 750 which dropped it (§5.5, "Direct-Store Interface Address Translation").
 * That makes this core the only post-601 one here whose T=1 segments are not
 * simply an error.
 *
 * A data access becomes a two-packet transaction on the direct-store
 * interface (§5.5.1, §7.2.3.1.3), and there is nothing behind it in this
 * model — no bus, no device — so it throws rather than inventing data, the
 * same scaffold hole the 601's non-memory-forced I/O segments leave
 * (cores/p601/p601_mmu.sail).
 *
 * A FETCH is a different matter and is architected: "the fetch access is to a
 * direct-store segment" is an ISI with SRR1[3] set (Table 1-2, §4.5.4), which
 * is Fault_DirectStore.  Instructions cannot be fetched over the interface at
 * all, so this needs no device.
 *
 * §5.5.3 additionally makes lwarx, stwcx., eciwx and ecowx unsupported in
 * these segments — DSI with DSISR[5] — which is the same rule the 601 states
 * in its §6.10.5 and which nonforced_io_segment already routes (ppc_mmu.sail,
 * ppc_insts_cache.sail). */
function core_direct_store(_ea, acc) =
  match acc {
    Mem_fetch => TR_Fault(Fault_DirectStore),
    _ => throw(Model_unimplemented("direct-store interface transaction"))
  }

/* Instruction address breakpoint (Table 2-4, §4.5.14): the word address in
 * IABR[CEA], enabled by IABR[BE], and — unlike the 603 — qualified by
 * IABR[TE], which "is compared with the MSR[IR] bit.  An IABR match is
 * signaled only if these bits also match."
 *
 * TIMING: §2.1.2.1 says "the instruction that triggers the instruction
 * address breakpoint exception is executed before the exception handler is
 * invoked", while §4.5.14 says it "is NOT executed before the exception
 * handler is invoked".  The manual contradicts itself outright.  §4.5.14
 * governs: it is the section written about this exception rather than about
 * the register, it is what the 604e manual says in the same place (§4.5.14),
 * and it is what the 603 (§2.1.2.6) and the 750 (§4.5.14) both do — a lone
 * 604 that ran the instruction first would be the odd one out among four
 * cores whose facility is otherwise identical.  So step() takes the exception
 * INSTEAD of executing, as it does on every core (ppc_step.sail). */
function core_inst_breakpoint(cia) =
  (IABR[BE] == 0b1)
  & (IABR[TE] == MSR[IT])
  & (cia[31 .. 2] == IABR[CEA])

/* The architected data address breakpoint, shared with the 604e and 750
 * (cores/common/ppc32_dabr.sail).  DSISR[9] is set for the match, which
 * Table 1-2 confirms for this core: "9 Set if an EA matches the address in
 * the DABR while in one of the three compare modes." */
function core_data_breakpoint(ea, width, is_store) =
  ppc32_data_breakpoint(ea, width, is_store)

$endif
