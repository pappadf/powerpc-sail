/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* main.sail — model entry point for the C emulator.
 *
 * A run is: reset, load a program, point NIA at it, run() until the program
 * halts itself (sc with the halt magic in GPR0 — see ppc_debug.sail) or a
 * step limit is exhausted, then dump the architected state.
 *
 * The program is either an ELF passed to the emulator with -e (the Sail C
 * runtime loads its segments into RAM before main() runs) or, with no -e,
 * the embedded smoke test below.
 *
 * TODO: this is a test harness, not a platform model:
 *  - Reset: architecturally the 601 comes up with MSR[EP]=1 and fetches
 *    from 0xFFF0_0100 (§5.4.1.2); loaded programs instead start at their
 *    entry point in real mode.
 *  - No devices: a program can only communicate through the halt status
 *    and the final state dump.
 */

$ifndef _PPC_MAIN
$define _PPC_MAIN

/* Entry point of the ELF the C runtime loaded, or 0 if none was given.
 * (Bound here rather than via the stdlib's elf.sail, whose bindings predate
 * the pure/impure annotation and would cost us a deprecation warning.) */
val elf_entry = impure "elf_entry" : unit -> int

val reset : unit -> unit
function reset() = {
  reset_common_regs();
  reset_reservation();
  core_reset();
  /* Reset exception: hard reset always vectors to 0xFFF0_0100 (§5.4.1.2) */
  NIA = 0xFFF00100;
  CIA = NIA
}

/* Embedded smoke-test program (until ELF loading is wired up).  The tail is
 * the halt sequence of the exit convention: build the magic in GPR0, set the
 * exit status in GPR3, sc.
 *
 *   0x1000: addi  r3, 0, 5       ; li r3, 5
 *   0x1004: addi  r4, 0, 7       ; li r4, 7
 *   0x1008: add.  r5, r3, r4     ; r5 = 12, CR0 = 0b0100 (GT)
 *   0x100c: stw   r5, 0x100(0)   ; MEM[0x100] = 12
 *   0x1010: lwz   r6, 0x100(0)   ; r6 = 12
 *   0x1014: addis r0, 0, 0x4600  ; lis r0, 0x4600  -+ halt magic
 *   0x1018: ori   r0, r0, 0x0D1E ;                 -+
 *   0x101c: addi  r3, 0, 0       ; exit status 0
 *   0x1020: sc                   ; halt
 */
val load_smoke_test : unit -> unit
function load_smoke_test() = {
  phys_write(0x00001000, 4, 0x38600005);
  phys_write(0x00001004, 4, 0x38800007);
  phys_write(0x00001008, 4, 0x7CA32215);  /* add. r5,r3,r4 (Rc=1)  */
  phys_write(0x0000100C, 4, 0x90A00100);
  phys_write(0x00001010, 4, 0x80C00100);  /* lwz r6, 0x100(0)      */
  phys_write(0x00001014, 4, 0x3C004600);  /* addis r0, 0, 0x4600   */
  phys_write(0x00001018, 4, 0x60000D1E);  /* ori r0, r0, 0x0D1E    */
  phys_write(0x0000101C, 4, 0x38600000);  /* addi r3, 0, 0         */
  phys_write(0x00001020, 4, 0x44000002)   /* sc                    */
}

val main : unit -> unit
function main() = {
  reset();
  debug_init();
  print_endline(concat_str("powerpc-sail: ", core_name()));

  /* Harness safety net for a program that never halts; the emulator's -l
   * flag can impose a tighter one. */
  step_limit = 100000;

  /* elf_entry() is 0 when no ELF was given on the command line. */
  let entry = elf_entry();
  if entry != 0 then {
    NIA = to_word(entry);
    print_bits("[boot] entry = ", NIA)
  } else {
    load_smoke_test();
    NIA = 0x00001000
  };

  let _ = run();
  dump_state()
}

$endif
