/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_insts_begin.sail — opens the scattered instruction definitions.
 *
 * Each instruction contributes, in whatever ppc_insts_*.sail (or core
 * p*_insts_*.sail) file it lives in:
 *
 *   union clause ast = MNEMONIC : (operand types...)
 *   mapping clause encdec = MNEMONIC(...) <-> <bit pattern>
 *   function clause execute(MNEMONIC(...)) = { ...; COMPLETED }
 *
 * plus one `mapping clause assembly` in ppc_assembly.sail (or the core's own
 * assembly file), which is what the -v 0x1 trace prints.
 *
 * The scattered definitions are closed in ppc_insts_end.sail, which also
 * provides the ILLEGAL fallback.
 *
 * Encoding notes:
 *  - primary opcode = instruction bits 0-5 (manual) = sail bits 31..26;
 *    writing encdec patterns left-to-right in manual field order with `@`
 *    gives the correct dec-order layout;
 *  - the `assembly` mapping (ast <-> text) is scattered the same way; its
 *    clauses live in ppc_assembly.sail so that the instruction files stay
 *    about behaviour.  Both are mappings, so each instruction is defined
 *    once and read in both directions.
 */

$ifndef _PPC_INSTS_BEGIN
$define _PPC_INSTS_BEGIN

scattered union ast

val execute : ast -> Completion
scattered function execute

val encdec : ast <-> bits(32)
scattered mapping encdec

val assembly : ast <-> string
scattered mapping assembly

$endif
