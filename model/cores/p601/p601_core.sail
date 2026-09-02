/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p601_core.sail — PowerPC 601 implementation of the core interface
 * declared in ppc_core_iface.sail. */

$ifndef _P601_CORE
$define _P601_CORE

function core_name() = "PowerPC 601"

/* PVR: version 0x0001 for the 601; the revision field is implementation-
 * defined (MPC601UM §2.3.3.11), and we use 0x0000. */
function core_pvr() = 0x00010000

/* MSR fields the 601 implements (Table 2-9): EE PR FP ME FE0 SE FE1 EP IT DT.
 * It has no POW, TGPR, ILE, BE, PM, RI or LE — little-endian mode is HID0[LM]
 * (§2.4.3), not an MSR bit.  Derived from the common Msr bitfield so that it
 * cannot drift from the field list it names. */
function core_msr_implemented() =
  [Mk_Msr(zeros(32)) with EE = 0b1, PR = 0b1, FP = 0b1, ME = 0b1, FE0 = 0b1,
                          SE = 0b1, FE1 = 0b1, EP = 0b1, IT = 0b1,
                          DT = 0b1].bits

/* Only the 25 most-significant bits of the DEC exist: manual bits 0-24, so
 * the low seven read as zero and a write ignores them (§2.3.3.5). */
function core_dec_implemented() = 0xFFFFFF80
/* Hard reset state, MPC601UM §2.7.1 / Table 2-11 / §5.4.1.2:
 * HID0 = 0x8001_0080; MSR: ME=1, EP=1, everything else 0; GPRs, MQ, RTC,
 * BATs etc. cleared; first fetch from 0xFFF0_0100. */
function core_reset() = {
  MQ = zeros(32);
  RTCU = zeros(32);
  RTCL = zeros(32);
  foreach (i from 0 to 3) {
    BATU[i] = zeros(32);
    BATL[i] = zeros(32)
  };
  HID0 = Mk_P601_Hid0(0x80010080);
  HID1 = Mk_P601_Hid1(zeros(32));
  IABR = Mk_P601_Iabr(zeros(32));
  DABR = Mk_P601_Dabr(zeros(32));
  PIR = zeros(32);
  tick_ns = rtc_tick_ns;   /* model parameter, see p601_regs.sail */
  rtc_ns_acc = 0;
  MSR[ME] = 0b1;
  MSR[EP] = 0b1
}

/* Advance the timers by one instruction's worth of model time.  Called once
 * per instruction from step().
 *
 * The RTC and the decrementer are driven by the same external 7.8125 MHz
 * oscillator, and the manual is explicit that they are coherent (§2.3.3.5.1)
 * — so one accumulator feeds both.  Every 128 ns the RTC counts up by one
 * tick and the DEC counts down by one; because the low seven bits of each
 * register do not exist, one tick is 128 in the register encoding.
 *
 * The accumulator only matters when tick_ns is set below 128, which is the
 * realistic case (see p601_regs.sail); at the default the loop below runs
 * exactly one tick per instruction. */
function core_tick() = {
  rtc_ns_acc = rtc_ns_acc + tick_ns;
  let ticks = tdiv_int(rtc_ns_acc, rtc_tick_ns);
  rtc_ns_acc = rtc_ns_acc - ticks * rtc_tick_ns;
  if ticks > 0 then {
    /* RTCL counts nanoseconds within the current second and carries into
     * RTCU on reaching one billion (§2.2.5.3.1-2).  Subtracting rather than
     * clearing keeps the remainder, which matters only if a tick could ever
     * straddle the boundary; it cannot, since 10^9 is a whole number of
     * 128 ns ticks, but it costs nothing to be exact. */
    harness_wrote(hw_rtcl);
    RTCL = (RTCL + ticks * rtc_tick_ns) & rtcl_implemented;
    if unsigned(RTCL) >= rtc_second_ns then {
      harness_wrote(hw_rtcl);
      RTCL = RTCL - rtc_second_ns;
      harness_wrote(hw_rtcu);
      RTCU = RTCU + 1
    };
    /* set_dec latches the exception request on the 0 -> 1 transition of
     * manual bit 0, the same path a mtspr to the DEC takes (§2.3.3.5). */
    set_dec(DEC - ticks * rtc_tick_ns)
  }
}

/* --- Debug facilities (§2.3.3.13) --------------------------------------- */

/* A machine check with MSR[ME] = 0 checkstops unless BOTH the master
 * checkstop enable and the machine-check checkstop enable are clear, in
 * which case the 601 takes the exception after all (§5.4.2, Table 2-22).
 * Note the reset value 0x8001_0080 has CE set and EM clear, so out of reset
 * a machine check with ME clear does checkstop. */
function core_checkstop_enabled() = (HID0[CE] | HID0[EM]) == 0b1

/* Instruction address compare (§5.4.12.1, Tables 2-23/2-24).  Only the
 * "trap to run mode exception" response is modellable, and of the compare
 * modes only the two instruction-address ones: 010 and 110 differ solely in
 * how many instructions reach the compared pipeline stage, which this model
 * — where every instruction is executed in order, individually — cannot
 * distinguish, so both are the same compare here.
 * TODO: mode 111 compares branch targets only, which needs step() to know
 * the fetch followed a taken branch; mode 100 is the HID single-instruction
 * step, which the manual warns loops forever when combined with RM = 10. */
/* The 601 has no instruction address breakpoint exception of its own: an
 * IABR match is reported as the run-mode exception (§5.4.12.1). */
function core_inst_breakpoint_exception() = E_RunMode

function core_inst_breakpoint(cia) =
  (HID1[RM] == 0b10)
  & ((HID1[M] == 0b010) | (HID1[M] == 0b110))
  & (cia[31 .. 2] == IABR[CEA])

/* Data address compare (§2.3.3.13.4, Table 2-26).  The DABR names one
 * double word and any overlap with it counts: "if any part of the load
 * access touches the double word specified in the DABR ... the DAE occurs".
 * An access is at most eight bytes wide, so it can straddle at most one
 * boundary and testing its first and last byte covers it.
 * SA enables the compare per direction: bit 31 for loads, bit 30 for stores.
 * lscbx and the cache control instructions are exempt (Table 2-26); they do
 * not reach this hook because neither goes through the mem_* accessors. */
function core_data_breakpoint(ea, width, is_store) = {
  let enabled = if is_store then DABR[SA][1] == bitone
                else DABR[SA][0] == bitone;
  let last = ea + (width - 1);
  enabled & ((ea[31 .. 3] == DABR[DAB]) | (last[31 .. 3] == DABR[DAB]))
}

/* Exception vector offsets, MPC601UM Table 5-2.  The 601 has no FP assist
 * (0x00E00) vector, and it does not use the architecture's trace vector
 * 0x00D00: MSR[SE] tracing lands on the run-mode vector 0x02000 alongside
 * the IABR breakpoint (§5.4.12).  Expressing that as a second entry pointing
 * at the same offset keeps the difference where it belongs — in the vector
 * table, which is already per-core — so common code can raise the
 * architectural E_Trace and let each core place it. */
function core_exception_vector(e) =
  match e {
    E_Reset         => 0x00000100,
    E_MachineCheck  => 0x00000200,
    E_DataAccess    => 0x00000300,
    E_InstAccess    => 0x00000400,
    E_External      => 0x00000500,
    E_Alignment     => 0x00000600,
    E_Program       => 0x00000700,
    E_FPUnavailable => 0x00000800,
    E_Decrementer   => 0x00000900,
    E_IOCtlError    => 0x00000A00,
    E_SystemCall    => 0x00000C00,
    E_RunMode       => 0x00002000,
    E_Trace         => 0x00002000,
    _               => throw(Model_internal_error("exception not implemented on the 601"))
  }

/* Endianness: HID0[LM] selects little-endian mode for both fetch and data
 * (§2.4.3).  The 601 has no MSR[LE]; the mode is address-munging rather than
 * byte-swapping, which lives in le_munge (ppc_mem.sail).
 *
 * Switching LM takes effect immediately here.  §2.4.3 requires software to
 * wrap the mtspr in three sync instructions either side, but that binds the
 * program rather than the processor, and the behaviour it guards against —
 * the mtspr taking effect twice, or some of those syncs not executing, both
 * depending on where the sequence starts — cannot arise in a model that
 * completes one instruction at a time. */
function core_bigendian() = HID0[LM] == 0b0

/* --- Alignment exceptions (§5.4.6.1) ------------------------------------ */

/* The 601's rules — the widest of the family's, because it is the one core
 * that faults on boundary crossings with translation OFF:
 *
 *  - Crossing a 256 MB boundary always faults, in every translation mode
 *    and whatever the alignment — including with translation off
 *    (§5.4.6.1.1, and Table 5-14's "the appropriate range check is
 *    performed before the instruction begins execution").
 *  - Under page-address translation (MSR[DT]=1 over a memory segment) a
 *    4 KB crossing faults as well; for a string or multiple only when the
 *    operand is not word-aligned (§3.5.6).  The manual is explicit that
 *    falling inside a BAT region does not exempt the access, so no BAT
 *    lookup is needed here.  Align_string_4k is the one string instruction
 *    (lscbx) whose 4 KB crossing faults "regardless of the starting
 *    address, even if the operand starts on a word boundary" (§5.4.6.1.4).
 *  - In LITTLE-ENDIAN mode the rules are far stricter (§5.4.6.3, §2.4.3.2):
 *    ANY misaligned operand faults, and EVERY string or multiple
 *    instruction faults whatever its address.  Both follow from the
 *    addressing being a munge of the low three address bits, which only
 *    lands where a little-endian program expects for a naturally aligned
 *    operand.
 *  - An I/O controller interface segment that is not memory-forced makes
 *    every FLOATING-POINT load and store fault whatever its alignment
 *    (§5.4.6.1.2).
 *
 * In big-endian mode the 601 handles every other misalignment in hardware
 * by splitting the access, so nothing else faults.  In particular a
 * misaligned lmw/stmw is EXECUTED (POWER compatibility, §3.5.5) and a
 * misaligned lwarx/stwcx./eciwx/ecowx that crosses nothing is boundedly
 * undefined and performed as written — Align_multiple and Align_atomic
 * carry no extra rule here, unlike on the later cores. */
function core_alignment_fault(ea, n, rule) = {
  let page_mode = (MSR[DT] == 0b1) & (rSR(ea[31 .. 28])[T] == 0b0);
  let four_k : bool = match rule {
    Align_string   => (ea[1 .. 0] != 0b00) & crosses_4k(ea, n),
    Align_multiple => (ea[1 .. 0] != 0b00) & crosses_4k(ea, n),
    _              => crosses_4k(ea, n)
  };
  let misaligned : bool = match rule {
    Align_operand => (n > 1) & (tmod_int(unsigned(ea), n) != 0),
    Align_fp      => (n > 1) & (tmod_int(unsigned(ea), n) != 0),
    Align_atomic  => ea[1 .. 0] != 0b00,
    Align_ext     => ea[1 .. 0] != 0b00,
    _             => true      /* a string or multiple always faults in LE */
  };
  let le_fault = not_bool(core_bigendian()) & misaligned;
  /* §5.4.6.1.2: "floating-point loads and stores to I/O controller
   * interface segments always cause an alignment exception, regardless of
   * operand alignment" — the memory-forced ones excepted, being ordinary
   * memory. */
  let io_fault : bool = match rule {
    Align_fp => nonforced_io_segment(ea),
    _        => false
  };
  crosses_256m(ea, n) | (page_mode & four_k) | le_fault | io_fault
}

/* DAR gets the computed EA (Table 5-13); the +4 quirk is the 603e's. */
function core_alignment_dar(ea, _rule) = ea

/* --- FPSCR (Table 2-1) --------------------------------------------------- */

/* Manual bit 20 (architecturally reserved), VXSOFT (21), VXSQRT (22) and
 * bit 29 are "not implemented in the 601" and read as zero.  In sail bit
 * positions that clears bits 11, 10, 9 and 2. */
function core_fpscr_implemented() = 0xFFFFF1FB

$endif
