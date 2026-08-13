/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_debug.sail — model harness state and debug output.
 *
 * NOTHING IN THIS FILE IS ARCHITECTURAL.  It exists so that a test program
 * running on the emulator can stop the model cleanly and so that the
 * resulting machine state can be printed in a stable, diffable format.
 *
 * Exit convention: a test program executes
 *
 *     sc     with GPR0 = 0x4600_0D1E  ("halt magic")
 *
 * which stops the run loop instead of taking a system call exception; GPR3
 * carries an exit status that is reported by the harness.  Any other sc
 * behaves architecturally.  The magic is checked in GPR0 (not in the sc
 * encoding) so that the instruction remains a plain, assemblable `sc`.
 *
 * Run-time switches come from the Sail C runtime's own command line:
 *   -v 0xN   verbosity word, used here as a bit set of debug switches
 *   -l N     cycle limit, an upper bound on executed instructions
 */

$ifndef _PPC_DEBUG
$define _PPC_DEBUG

/* --- Run-time switches -------------------------------------------------- */

/* The C runtime stores the -v argument and hands it back as a 64-bit word,
 * intended to be used as individual debug switches. */
val sail_get_verbosity = impure "sail_get_verbosity" : unit -> bits(64)

/* -v bit 0: print one trace line per executed instruction. */
register trace_enabled : bool

/* True once the -l cycle limit has been reached; NOTE this call counts a
 * cycle, so it must be called exactly once per instruction. */
val cycle_limit_reached = impure "cycle_limit_reached" : unit -> bool

val debug_init : unit -> unit
function debug_init() = {
  trace_enabled = sail_get_verbosity()[0] == bitone
}

/* --- Halt request ------------------------------------------------------- */

/* GPR0 value that turns `sc` into a halt request. */
let halt_magic : word = 0x46000D1E

register halt_req : bool        /* set by request_halt(); polled by run()  */
register halt_status : word /* exit status supplied by the program     */

val request_halt : word -> unit
function request_halt(status) = {
  halt_req = true;
  halt_status = status
}

/* --- Checkstop ---------------------------------------------------------- */

/* The checkstop state IS architectural (§5.4.2.2: a machine check with
 * MSR[ME] = 0 suspends instruction processing until the processor is reset),
 * but "stop the emulator and say so" is the harness's job, which is why the
 * flag lives here next to the halt request rather than in the exception
 * code.  It is deliberately separate from halt_req: a checkstop is a
 * failure, and a test that reaches one should not look like one that ran to
 * a clean HALT. */
register checkstop_req : bool

val request_checkstop : unit -> unit
function request_checkstop() = { checkstop_req = true }

/* --- Run limits --------------------------------------------------------- */

/* Maximum number of instructions a run may execute before the harness gives
 * up (0 = unlimited).  A limit is the model's only defence against a test
 * program that never reaches its halt instruction; the emulator's -l flag
 * imposes a second, independent one (whichever is hit first wins). */
register step_limit : int

/* --- State dump --------------------------------------------------------- */

/* Label helper: "r00 = ", "r31 = ", ... — fixed width so that dumps line up
 * and diff cleanly against expected-output files. */
val reg_label : forall 'n, 0 <= 'n <= 31. int('n) -> string
function reg_label(i) =
  concat_str("r", concat_str(if i < 10 then "0" else "",
                             concat_str(dec_str(i), "   = ")))

/* Print the programmer-visible common state in a stable format.  Core
 * registers (MQ, RTC, BATs, HIDs on the 601) are deliberately not printed
 * here: this file is common, and timer values are not reproducible.  Add a
 * core hook if a core ever needs to contribute to the dump. */
val dump_state : unit -> unit
function dump_state() = {
  print_endline("--- state ---");
  print_bits("CIA   = ", CIA);
  print_bits("NIA   = ", NIA);
  print_bits("MSR   = ", MSR.bits);
  print_bits("CR    = ", CR);
  print_bits("XER   = ", XER.bits);
  print_bits("LR    = ", LR);
  print_bits("CTR   = ", CTR);
  print_bits("SRR0  = ", SRR0);
  print_bits("SRR1  = ", SRR1);
  print_bits("DAR   = ", DAR);
  print_bits("DSISR = ", DSISR);
  foreach (i from 0 to 31) {
    print_bits(reg_label(i), GPRs[i])
  };
  print_endline("--- end state ---")
}

$endif
