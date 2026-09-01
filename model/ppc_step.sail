/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_step.sail — the fetch / decode / execute step function. */

$ifndef _PPC_STEP
$define _PPC_STEP

/* Is a trace exception allowed after this instruction?  §5.4.12.2: the trace
 * exception fires "after each instruction that completes without causing a
 * exception or context change (such as a sc, rfi, ...)".  The exception half
 * of that is the Completion result; this is the context-change half.
 * TODO-VERIFY(§5.4.12.2): mtmsr also changes context and is not named.  It
 * cannot produce a spurious trace by SETTING MSR[SE] — the caller requires
 * the bit set both before and after — but an mtmsr that leaves SE set does
 * trace here. */
val traceable : ast -> bool
function traceable(inst) =
  match inst {
    SC(_)  => false,
    RFI()  => false,
    _      => true
  }

/* Is this a branch instruction, for the branch trace enabled by MSR[BE]?
 * "A trace exception is taken when MSR[SE] = 1 or when the currently
 * completing instruction is a branch and MSR[BE] = 1" (MPC603EUM Table 4-2,
 * and the same wording in MPC604UM Table 1-2 and MPC750UM Table 1-5).
 * The four branch instructions are the whole of the branch class: b, bc and
 * the two register forms (ppc_insts_branch.sail).  The condition register
 * logical instructions sit in the same chapter but are not branches, and
 * neither is sc — which traceable() excludes for a different reason.
 *
 * The 601 has no MSR[BE] (it is reserved there, so core_msr_implemented holds
 * it at zero), which is why this needs no core hook: the test below can never
 * fire on that core. */
val is_branch : ast -> bool
function is_branch(inst) =
  match inst {
    B(_)     => true,
    BC(_)    => true,
    BCLR(_)  => true,
    BCCTR(_) => true,
    _        => false
  }

/* Execute one instruction.  Returns false if the model should stop — that
 * is a harness condition (the halt request or a checkstop, both in
 * ppc_debug.sail), never an ordinary architectural one: exceptions redirect
 * control flow and keep running. */
val step : unit -> bool
function step() = {
  /* Asynchronous interrupts are taken between instructions, in the priority
   * order of Table 5-3 (§5.1.2). */
  let _ = check_interrupts();

  harness_wrote(hw_cia);
  CIA = NIA;
  harness_wrote(hw_nia);
  NIA = CIA + 4;

  match translate_addr(CIA, Mem_fetch) {
    TR_Fault(cause) => inst_access_fault(cause),
    TR_Address(pa, _) => {
      let instr = phys_fetch(pa);
      /* Latched for the alignment exception's DSISR image, which the
       * architecture defines in terms of the instruction encoding
       * (Table 5-13) — see dsisr_align_image in ppc_exceptions.sail. */
      cur_instr = instr;
      let inst_ast = encdec(instr);
      /* One trace line per instruction: address, raw word, disassembly, in
       * the layout objdump uses so the two can be read side by side.  The
       * disassembly is the forwards direction of the `assembly` mapping
       * (ppc_assembly.sail); an unrecognized word prints as `.long`. */
      if trace_enabled then
        print_endline(concat_str("[trace] ",
                      concat_str(bits_str(CIA),
                      concat_str("  ",
                      concat_str(bits_str(instr),
                      concat_str("  ", assembly(inst_ast)))))));
      /* Instruction address breakpoint (§5.4.12.1): the compare happens at
       * decode and the exception is taken INSTEAD of executing, so SRR0
       * addresses the instruction that did not run.  Priority 3,
       * instruction-dependent (Table 5-3).  Which exception it is differs by
       * core — run-mode at 0x02000 on the 601, a dedicated instruction
       * address breakpoint exception at 0x01300 on every later core — so the
       * core names it (core_inst_breakpoint_exception). */
      if core_inst_breakpoint(CIA) then
        take_exception(core_inst_breakpoint_exception(), CIA, 0x0000)
      else {
        let se_before = MSR[SE];
        let be_before = MSR[BE];
        let completion = execute(inst_ast);
        /* Trace exception (§5.4.12.2), which the 601 vectors to 0x02000
         * alongside the run-mode exception rather than to the
         * architecture's 0x00D00 — core_exception_vector places it.
         * SRR0 is the NEXT instruction (Table 5-25), unlike the run-mode
         * exception above.  MSR[SE] is required both before and after the
         * instruction: clearing it ends tracing "immediately" (§5.4.12.1),
         * and setting it should not trace the instruction that set it.
         * take_exception then clears SE, as Table 5-6 requires. */
        match completion {
          COMPLETED =>
            if (se_before == 0b1) & (MSR[SE] == 0b1) & traceable(inst_ast)
            then take_exception(E_Trace, NIA, 0x0000)
            /* Branch trace, MSR[BE] (MPC603EUM Table 4-2).  Same vector and
             * same SRR0 as the single-step trace; the two are one exception
             * with two enables, so a branch with both bits set traces once.
             * BE is read before and after for the same reason SE is: an
             * instruction that changes it should not trace on the new value.
             * No core that has BE excludes any branch from it, and the ones
             * traceable() excludes are not branches. */
            else if (be_before == 0b1) & (MSR[BE] == 0b1) & is_branch(inst_ast)
            then take_exception(E_Trace, NIA, 0x0000),
          EXCEPTION_TAKEN => ()
        }
      }
    }
  };

  core_tick();
  not_bool(halt_req) & not_bool(checkstop_req)
}

/* Run until the program halts (see the exit convention in ppc_debug.sail) or
 * a step limit is exhausted.  Returns the number of instructions executed.
 *
 * Step limits are a harness safety net, not a model of anything: the
 * step_limit register holds the model's own default and the emulator's -l
 * flag imposes a second one, whichever is reached first. */
val run : unit -> int
function run() = {
  halt_req = false;
  checkstop_req = false;
  halt_status = zeros(32);
  var steps : int = 0;
  var running : bool = true;
  while running do {
    running = step();
    steps = steps + 1;
    if cycle_limit_reached() then running = false;
    if (step_limit > 0) & (steps >= step_limit) then running = false
  };
  if checkstop_req then
    /* §5.4.2.2: processing is suspended and cannot be restarted without
     * resetting the processor.  Reported separately from a clean halt. */
    print_endline("[checkstop] machine check with MSR[ME] = 0")
  else if halt_req then
    print_bits("[halt] status = ", halt_status)
  else
    print_endline(concat_str("[halt] step limit reached after ",
                             concat_str(dec_str(steps), " instructions")));
  steps
}

$endif
