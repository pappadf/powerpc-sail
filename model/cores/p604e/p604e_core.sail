/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p604e_core.sail — PowerPC 604e implementation of the parts of the core
 * interface not shared with the other post-601 cores;
 * cores/common/ppc32_core.sail supplies the rest.
 * Reference: MPC604EUM.
 *
 * Every hook below is the 604's behaviour with a different PVR and a longer
 * reset, which is the honest summary of the two cores' relationship at this
 * level of description — see p604e_regs.sail for what the 604e actually adds.
 * The two are separate directories rather than one parameterised core so that
 * each reads as a description of one part. */

$ifndef _P604E_CORE
$define _P604E_CORE

function core_name() = "PowerPC 604e"

/* PVR: "the processor version number is 9 for the 604e.  The processor
 * revision level starts at 0x0100 and changes for each chip revision"
 * (§2.1.1 implementation note).  As elsewhere in this model the revision is
 * left at 0x0000 rather than picking one silicon revision to imitate. */
function core_pvr() = 0x00090000

/* MSR fields (Table 4-3): identical to the 604's — POW ILE EE PR FP ME FE0 SE
 * BE FE1 IP IR DR PM RI LE, with bit 14 reserved.  PM is described in the
 * same words as the 604's ("this bit is specific to the 604e"). */
function core_msr_implemented() =
  [Mk_Msr(zeros(32)) with POW = 0b1, ILE = 0b1, EE = 0b1, PR = 0b1, FP = 0b1,
                          ME = 0b1, FE0 = 0b1, SE = 0b1, BE = 0b1, FE1 = 0b1,
                          EP = 0b1, IT = 0b1, DT = 0b1, PM = 0b1, RI = 0b1,
                          LE = 0b1].bits

/* Hard reset.  Like the 604 manual, MPC604EUM does not tabulate the reset
 * values; see the note in cores/p604/p604_core.sail for where this state
 * comes from and why. */
function core_reset() = {
  ppc32_reset_regs();
  DABR = Mk_Ppc32_Dabr(zeros(32));
  HID1 = zeros(32);
  PIR = zeros(32);
  MMCR0 = zeros(32);
  MMCR1 = zeros(32);
  PMC1 = zeros(32);
  PMC2 = zeros(32);
  PMC3 = zeros(32);
  PMC4 = zeros(32);
  SIA = zeros(32);
  SDA = zeros(32);
  DEC = 0xFFFFFFFF;
  MSR[EP] = 0b1
}

/* Exception vector offsets, Table 1-2 / §4.5 — the same set as the 604,
 * including the 0x00F00 performance monitor interrupt and excluding both the
 * 0x00E00 floating-point assist and the 603's three TLB miss vectors. */
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
    _                  => throw(Model_internal_error("exception not implemented on the 604e"))
  }

/* Direct-store: implemented, as on the 604 (§5.5).  See the discussion in
 * cores/p604/p604_core.sail — a data access needs a bus this model does not
 * have, while a fetch is an architected ISI with SRR1[3]. */
function core_direct_store(_ea, acc) =
  match acc {
    Mem_fetch => TR_Fault(Fault_DirectStore),
    _ => throw(Model_unimplemented("direct-store interface transaction"))
  }

/* Instruction address breakpoint (Table 2-5, §4.5.14): as the 604, including
 * the IABR[TE] against MSR[IR] qualification.  §4.5.14 here states without
 * the 604 manual's self-contradiction that the instruction "is not executed
 * before the exception handler is invoked". */
function core_inst_breakpoint(cia) =
  (IABR[BE] == 0b1)
  & (IABR[TE] == MSR[IT])
  & (cia[31 .. 2] == IABR[CEA])

function core_data_breakpoint(ea, width, is_store) =
  ppc32_data_breakpoint(ea, width, is_store)

$endif
