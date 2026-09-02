/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p603_core.sail — PowerPC 603 implementation of the parts of the core
 * interface (ppc_core_iface.sail) that are not shared with the other post-601
 * cores; cores/common/ppc32_core.sail supplies the rest.
 *
 * SOURCE.  MPC603EUM, which is the 603e manual — the only 603-family manual
 * this transcription has.  Where it distinguishes the 603 from the PID6-603e
 * and PID7t-603e the difference is noted at the point it matters; there are
 * three that touch architected state, and all three are recorded below. */

$ifndef _P603_CORE
$define _P603_CORE

function core_name() = "PowerPC 603"

/* PVR (SPR 287).  THE MANUAL CONTRADICTS ITSELF and the two statements are
 * not reconcilable:
 *
 *  - §1.3.1.1 and §2.1.1: "the processor version number is 6 for the
 *    PID6-603e and 7 for the PID7t-603e";
 *  - Table 4-9, the hard-reset settings: "PVR  0003000n".
 *
 * They are describing different parts: the implementation notes describe the
 * two 603e silicon revisions the manual was rewritten for, and the reset table
 * is inherited from the original 603 it was rewritten FROM, whose version
 * number is 3.  Neither is a mistake in its own context.
 *
 * This core is the 603, so it takes 0x0003 — the value Table 4-9 gives, and
 * the value real 603 silicon reports.  A 603e model differing only here would
 * use 0x0006 or 0x0007.  The revision is implementation-defined and this model
 * uses 0x0000, as it does for the 601. */
function core_pvr() = 0x00030000

/* MSR fields the 603 implements (Table 4-6): POW TGPR ILE EE PR FP ME FE0 SE
 * BE FE1 IP IR DR RI LE.  TGPR is 603-specific and no other core in this model
 * has it; PM (manual bit 29) arrives with the 604e and is absent here.
 * Derived from the common Msr bitfield so it cannot drift from the field list
 * it names. */
function core_msr_implemented() =
  [Mk_Msr(zeros(32)) with POW = 0b1, TGPR = 0b1, ILE = 0b1, EE = 0b1, PR = 0b1,
                          FP = 0b1, ME = 0b1, FE0 = 0b1, SE = 0b1, BE = 0b1,
                          FE1 = 0b1, EP = 0b1, IT = 0b1, DT = 0b1, RI = 0b1,
                          LE = 0b1].bits

/* Hard reset state, Table 4-9.  MSR = 0x0000_0040 is IP alone — note that,
 * unlike the 601, the 603 comes out of reset with ME CLEAR, so a machine check
 * before software sets it goes straight to checkstop.  DEC = 0xFFFF_FFFF, and
 * HID0, HID1, IABR, the time base and the table search registers all clear.
 *
 * The table calls the GPRs, FPRs, SRs, BATs and TLBs "unknown"; this model
 * zeroes them (reset_common_regs and ppc32_reset_regs), which is the choice it
 * makes everywhere for "undefined at reset" and is what keeps a reset run
 * reproducible. */
function core_reset() = {
  ppc32_reset_regs();
  HID1 = zeros(32);
  DMISS = zeros(32);
  IMISS = zeros(32);
  DCMP = zeros(32);
  ICMP = zeros(32);
  HASH1 = zeros(32);
  HASH2 = zeros(32);
  RPA = zeros(32);
  DEC = 0xFFFFFFFF;
  MSR[EP] = 0b1
}

/* Exception vector offsets, Table 4-2.
 *
 * THE THREE TLB MISS VECTORS ARE A KNOWN DIVERGENCE, not an omission, and
 * this is the place to argue it.  The 603 reloads its TLBs in software: a miss
 * in the ITLB raises 0x01000, a miss in the DTLB raises 0x01100 for a load and
 * 0x01200 for a store (and 0x01200 also when a hit needs the changed bit set),
 * and the handler walks the page table and installs the entry with tlbld or
 * tlbli.
 *
 * This model has NO TLB — ppc_mmu.sail walks the page table on every access
 * and never caches the result, deliberately, and that decision predates this
 * core.  A machine with no TLB never misses in one, so none of the three
 * exceptions can arise, and mapping them here would be mapping something
 * unreachable.  They are still listed, because a core that DID model the TLB
 * would place them here and because listing them documents which offsets the
 * 603 uses; what makes them unreachable is the MMU, not this table.
 *
 * What survives the divergence is the architectural OUTCOME.  A genuine page
 * fault — no PTE anywhere in either PTEG — reaches the handler on hardware as
 * a TLB miss, the handler's search fails, and it branches to the DSI or ISI
 * path; here the same page fault raises DSI or ISI directly (page_translate,
 * ppc_mmu.sail).  Same exception, same DSISR/SRR1 image, same handler; only
 * the intermediate trip through the miss handler is missing.  What does NOT
 * survive is a program that depends on the miss exception itself — one that
 * counts them, or that installs TLB entries describing something other than
 * what the page table says.
 *
 * The 603 has no 0x00E00 floating-point assist and no 0x00F00 performance
 * monitor vector: "the MPC603e does not generate an exception to this vector"
 * for 0x00E00, and the performance monitor is a 604 and 750 facility. */
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
    E_ITLBMiss         => 0x00001000,
    E_DTLBMissLoad     => 0x00001100,
    E_DTLBMissStore    => 0x00001200,
    E_InstBreakpoint   => 0x00001300,
    E_SystemManagement => 0x00001400,
    _                  => throw(Model_internal_error("exception not implemented on the 603"))
  }

/* Direct-store: REMOVED on this core.  "Support for access to direct-store
 * segments has been removed" (§1.1.1), and Table 4-2 gives the consequences —
 * a data access to a segment with T=1 is a DSI with DSISR[5] set, and a fetch
 * is an ISI with SRR1[3] set.  Both are Fault_DirectStore, whose two images
 * are in ppc_exceptions.sail.
 *
 * Note this is the same outcome the 750 produces and a different one from the
 * 604, which still implements the interface. */
function core_direct_store(_ea, _acc) = TR_Fault(Fault_DirectStore)

/* Instruction address breakpoint (Table 2-8, §4.5.13): the compare is on the
 * word address, manual bits 0-29, and IABR[BE] enables it.
 *
 * Unlike the 604 and 750, bit 31 is RESERVED on this core — Table 2-8 defines
 * bits 0-29 and 30 and stops — so there is no IABR[TE] test against MSR[IR]
 * here.  The shared bitfield names the bit anyway (ppc32_regs.sail); this core
 * simply does not read it. */
function core_inst_breakpoint(cia) =
  (IABR[BE] == 0b1) & (cia[31 .. 2] == IABR[CEA])

/* No data address breakpoint facility: the DABR is an OPTIONAL architected
 * register (MPCFPE32B §2.3.14) and Table 2-40, which lists the whole of this
 * core's implementation-specific SPR set, does not include it.  So the compare
 * never fires and the SPR is not in p603_sprs.sail. */
function core_data_breakpoint(_ea, _width, _is_store) = false

/* Alignment (§4.5.6): the shared §4.5.6 rules, with this core's three
 * particulars — Table 4-15's 4 KB page-translation crossing rule (the only
 * boundary rule any of the later cores keeps), NO big-endian string
 * boundary rule (the 604/750 string sentence does not appear in this
 * manual), and the floating-point direct-store fault (§4.5.6 bullet). */
function core_alignment_fault(ea, n, rule) =
  ppc32_alignment_fault(true, false, true, ea, n, rule)

/* "When the operand of an lmw, stmw, lwarx, or stwcx. instruction is not
 * word-aligned, that address value +4 is stored into the DAR" (Table 4-14
 * and §4.5.6.2) — a documented quirk of this core alone. */
function core_alignment_dar(ea, rule) =
  match rule {
    Align_multiple => if ea[1 .. 0] != 0b00 then ea + 4 else ea,
    Align_atomic   => if ea[1 .. 0] != 0b00 then ea + 4 else ea,
    _              => ea
  }

$endif
