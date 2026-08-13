/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_exceptions.sail — exception (interrupt) mechanism, MPC601UM ch. 5.
 *
 * Vector offsets are supplied per-core (core_exception_vector) because the
 * implemented set differs: 601 adds 0x00A00 (I/O controller error) and
 * 0x02000 (run-mode), and does not use 0x00D00 trace / 0x00E00 FP assist.
 */

$ifndef _PPC_EXCEPTIONS
$define _PPC_EXCEPTIONS

/* Base address selected by MSR[EP]: 0x000n_nnnn or 0xFFFn_nnnn
 * (MPC601UM §5.4, Table 5-2). */
val exception_base : unit -> bits(32)
function exception_base() =
  if MSR[EP] == 0b1 then 0xFFF00000 else 0x00000000

/* Take an exception: save state in SRR0/SRR1, update MSR, redirect NIA.
 *
 * srr0_val: address to save (faulting instruction, next instruction, ...
 *           — WHICH ONE depends on the exception type and is the caller's
 *           responsibility; see MPC601UM §5.4.x per exception).
 * srr1_hi:  exception-specific SRR1 bits, manual bits 0-15 (sail 31..16).
 *
 * NOTE on the run-mode exception, whose Table 5-23 says SRR1 is "loaded from
 * bits 0-31 of the MSR" rather than the usual "0-15 cleared, 16-31 from the
 * MSR": on the 601 those are the same value.  Every MSR bit above 15 is
 * reserved and reads as zero (§2.3.1, and msr_implemented enforces it), so a
 * whole-MSR save and a zero high half are indistinguishable, and no separate
 * entry point is needed.  A core with an MSR bit in 0-15 — a 64-bit
 * implementation's SF, say — would need one.
 *
 * Any reservation is dropped here, which covers two of §3.5.7's five ways to
 * lose one in a single place: "execution of an instruction that causes an
 * exception" and "occurrence of an asynchronous exception" (also §5.2.2
 * step 6).
 */
val take_exception : (PPCException, word, bits(16)) -> unit
function take_exception(e, srr0_val, srr1_hi) = {
  clear_reservation();
  SRR0 = srr0_val;
  /* SRR1 = exception-specific high half @ MSR[16:31] (manual numbering) */
  SRR1 = srr1_hi @ MSR.bits[15 .. 0];
  /* MSR update on exception entry (Table 5-6): clear EE PR FP FE0 SE FE1
   * IT DT; EP unaltered; ME unaltered except that a machine check clears it,
   * so that a second one checkstops rather than losing the saved state. */
  match e {
    E_MachineCheck => MSR[ME] = 0b0,
    _              => ()
  };
  MSR[EE] = 0b0;
  MSR[PR] = 0b0;
  MSR[FP] = 0b0;
  MSR[FE0] = 0b0;
  MSR[SE] = 0b0;
  MSR[FE1] = 0b0;
  MSR[IT] = 0b0;
  MSR[DT] = 0b0;
  NIA = exception_base() | core_exception_vector(e)
}

/* Convenience wrappers ---------------------------------------------------- */

/* Program exception (§5.4.7).  SRR1 manual bits: 11 = FP-enabled,
 * 12 = illegal instruction, 13 = privileged instruction, 14 = trap,
 * 15 = SRR0 points to next instruction.
 *
 * Bit 15 is always CLEAR on the 601 and needs no case analysis: it says SRR0
 * holds the address of a later instruction rather than the excepting one,
 * and the only cause that could do that is a floating-point enabled
 * exception reported imprecisely.  The 601 has no imprecise mode — FE0 and
 * FE1 are OR-ed (Table 2-10, see fp_exceptions_enabled) — so §5.4.7 states
 * outright that "all program exceptions taken on behalf of a floating-point
 * enabled exception clear SRR1[15]".  The other three causes point at the
 * excepting instruction by definition. */
val program_exception : ProgramCause -> Completion
function program_exception(cause) = {
  let srr1_hi : bits(16) =
    match cause {
      Prog_FPEnabled  => 0x0010,  /* manual bit 11 -> bit 4 of hi half */
      Prog_Illegal    => 0x0008,  /* manual bit 12 */
      Prog_Privileged => 0x0004,  /* manual bit 13 */
      Prog_Trap       => 0x0002   /* manual bit 14 */
    };
  take_exception(E_Program, CIA, srr1_hi);
  EXCEPTION_TAKEN
}

val fp_unavailable_exception : unit -> Completion
function fp_unavailable_exception() = {
  take_exception(E_FPUnavailable, CIA, 0x0000);
  EXCEPTION_TAKEN
}

/* Data access exception (§5.4.3): DSISR and DAR must be set by the caller
 * before calling this — data_access_fault below does that for a translation
 * fault, and eciwx/ecowx set DSISR[11] themselves. */
val data_access_exception : unit -> Completion
function data_access_exception() = {
  take_exception(E_DataAccess, CIA, 0x0000);
  EXCEPTION_TAKEN
}

/* DSISR image for a failed translation of a data access (Table 5-10).  Bit 6
 * records the direction of the access whatever the cause. */
val dsisr_of_fault : (FaultCause, bool) -> word
function dsisr_of_fault(cause, is_store) = {
  let cause_bit : word =
    match cause {
      Fault_PageFault        => 0x40000000,  /* manual bit 1 */
      Fault_Protection       => 0x08000000,  /* manual bit 4 */
      Fault_IOSegUnsupported => 0x04000000,  /* manual bit 5 */
      Fault_DataBreakpoint   => 0x00400000,  /* manual bit 9 */
      /* A fetch fault cannot reach the data path. */
      Fault_IOSegFetch       => zeros(32)
    };
  cause_bit | (if is_store then 0x02000000 else zeros(32))  /* manual bit 6 */
}

/* Take the data access exception a translation fault calls for (§5.4.3).
 * DAR holds the effective address of the access (Table 5-10). */
val data_access_fault : (FaultCause, word, bool) -> Completion
function data_access_fault(cause, ea, is_store) = {
  DAR = ea;
  DSISR = dsisr_of_fault(cause, is_store);
  data_access_exception()
}

/* Take the instruction access exception a translation fault calls for
 * (§5.4.4).  SRR0 is the address of the instruction that would have been
 * executed next, i.e. the one we failed to fetch (Table 5-11).
 *
 * A page fault sets both bit 1 ("not found in the primary HTEG, the rehashed
 * secondary HTEG, or the range of a BAT register") and bit 10 ("the page
 * table search fails to find a translation"), which describe the same event
 * from two angles; Table 6-3 mentions only bit 1.
 * 601 deviation: a fetch from an I/O controller interface segment sets NO
 * bits at all, where the architecture sets bit 3 (Table 5-11, Table 6-3). */
val inst_access_fault : FaultCause -> unit
function inst_access_fault(cause) = {
  let srr1_hi : bits(16) =
    match cause {
      Fault_PageFault  => 0x4020,  /* manual bits 1 and 10 */
      Fault_Protection => 0x0800,  /* manual bit 4         */
      _                => 0x0000
    };
  take_exception(E_InstAccess, CIA, srr1_hi)
}

/* DSISR left behind by an alignment exception (§5.4.6, Table 5-13).  The
 * handler emulates the excepting instruction, and rather than re-fetch it,
 * it reads a re-encoding of the opcode out of DSISR; Table 5-15 is the
 * inverse mapping.  Manual bit numbering throughout, so sail index 31 - i:
 *
 *   0-14  cleared
 *   15-16 instruction bits 29-30 (X-form) / cleared (D-form)
 *   17    instruction bit 25    (X-form) / bit 5    (D-form)
 *   18-21 instruction bits 21-24 (X-form) / bits 1-4 (D-form)
 *   22-26 instruction bits 6-10  (the source or destination register)
 *   27-31 instruction bits 11-15 (rA)
 *
 * "X-form" here means register indirect with index addressing, which for
 * every load and store is exactly primary opcode 31. */
val dsisr_align_image : bits(32) -> word
function dsisr_align_image(instr) = {
  let xform = instr[31 .. 26] == 0b011111;
  let f15_16 : bits(2) = if xform then instr[2 .. 1] else 0b00;
  let f17    : bits(1) = if xform then [instr[6]] else [instr[26]];
  let f18_21 : bits(4) = if xform then instr[10 .. 7] else instr[30 .. 27];
  zeros(15) @ f15_16 @ f17 @ f18_21 @ instr[25 .. 21] @ instr[20 .. 16]
}

/* Alignment exception (§5.4.6): DSISR[15:21] identifies the instruction for
 * software emulation (Table 5-15), DAR holds the EA the instruction
 * computed.  UNDEF: DSISR[22:26] is undefined for dcbz (Table 5-13); the
 * generic image is used there too. */
val alignment_exception : word -> Completion
function alignment_exception(ea) = {
  DAR = ea;
  DSISR = dsisr_align_image(cur_instr);
  take_exception(E_Alignment, CIA, 0x0000);
  EXCEPTION_TAKEN
}

/* --- Asynchronous, imprecise exceptions (Table 5-3 priorities 1 and 2) --- */

/* Soft reset (§5.4.1.1), the highest-priority exception of all.  Not
 * maskable, and SRR0 is the instruction that would have run next.
 *
 * Table 5-7 adds "if the processor state is corrupted to the extent that
 * execution cannot be reliably restarted, SRR1[30] is cleared".  On the 601
 * that rule is vacuous: manual bit 30 is reserved in the MSR and reads as
 * zero, so SRR1[30] — which is copied from it — is always zero anyway.  The
 * bit is MSR[RI] on cores that have one, and there the rule has teeth.
 *
 * Nothing calls this: a soft reset comes from the SRESET pin and there is no
 * platform to assert it.  Hard reset is the reset() path in main.sail. */
val soft_reset_exception : unit -> unit
function soft_reset_exception() = take_exception(E_Reset, NIA, 0x0000)

/* Machine check (§5.4.2), priority 2 and also not maskable by MSR[EE].
 *
 * With MSR[ME] set the exception is taken and entry clears ME, so a second
 * machine check before the handler restores it goes to checkstop instead of
 * overwriting the saved state.  With ME already clear the machine stops:
 * "instruction processing is suspended and generally cannot be restarted
 * without resetting the processor" (§5.4.2.2), which the model represents as
 * a clean halt carrying a message rather than as anything architectural.
 * The 601 qualifies even that — with both HID0 checkstop enables clear the
 * exception is taken despite ME (Table 2-22) — which is what the
 * core_checkstop_enabled hook answers.
 *
 * Nothing calls this either: the trigger is the TEA bus signal, and the bus
 * is out of scope.  SRR0 is the next instruction (Table 5-9). */
val machine_check_exception : unit -> unit
function machine_check_exception() =
  if (MSR[ME] == 0b1) | not_bool(core_checkstop_enabled()) then
    take_exception(E_MachineCheck, NIA, 0x0000)
  else
    request_checkstop()

/* --- Asynchronous, precise exceptions (Table 5-3 priorities 4 and 5) ----- */

/* Check for a pending asynchronous exception before fetching the next
 * instruction, in the priority order of Table 5-3.  Returns true if one was
 * taken (NIA then points at the handler).
 *
 * Reset and machine check outrank everything and ignore MSR[EE], but neither
 * has a source in this model, so only the two maskable ones are polled here;
 * were a source added, its poll would go above these two.  External beats
 * decrementer, and the decrementer request is cancelled by being taken
 * (§5.4.9) while the external one persists until its source drops — the
 * INT signal is level-sensitive and "must be held active until the 601 takes
 * the interrupt" (§5.4.5).
 *
 * Instruction-caused (synchronous) exceptions sit between the two groups at
 * priority 3; they are raised by execute() and by the fetch path in step(),
 * which runs after this check, so program order takes care of the ordering
 * on its own. */
val check_interrupts : unit -> bool
function check_interrupts() =
  if MSR[EE] == 0b0 then false
  else if ext_int_pending then {
    take_exception(E_External, NIA, 0x0000);
    true
  } else if DEC_pending then {
    DEC_pending = false;
    take_exception(E_Decrementer, NIA, 0x0000);
    true
  } else
    false

$endif
