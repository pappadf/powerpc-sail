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
    RTCL = (RTCL + ticks * rtc_tick_ns) & rtcl_implemented;
    if unsigned(RTCL) >= rtc_second_ns then {
      RTCL = RTCL - rtc_second_ns;
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

$endif
