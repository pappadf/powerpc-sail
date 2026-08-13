/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_insts_end.sail — closes every scattered definition.  This file MUST
 * come after all instruction files (common and core) in the build order;
 * its fallback clauses must be the last ones declared. */

$ifndef _PPC_INSTS_END
$define _PPC_INSTS_END

/* Any word that matched no encdec clause decodes to ILLEGAL. */
union clause ast = ILLEGAL : bits(32)

mapping clause encdec = ILLEGAL(instr) <-> instr : bits(32)

/* Illegal/reserved/unimplemented opcode -> program exception with SRR1
 * manual bit 12 set (MPC601UM §5.4.7).  NOTE: invalid FORMS of implemented
 * instructions must NOT trap (boundedly undefined) — that is handled per
 * instruction, not here.  So is E_FPUnavailable for the floating-point
 * opcodes when MSR[FP]=0 (fp_unavailable, ppc_insts_fp.sail). */
function clause execute(ILLEGAL(_)) =
  program_exception(Prog_Illegal)

/* An unrecognized word disassembles as the directive one would write to
 * reproduce it. */
mapping clause assembly = ILLEGAL(instr) <-> ".long" ^ spc() ^ hex_bits_32(instr)

end ast
end execute
end encdec
end assembly

/* Close the scattered SPR accessors (ppc_sprs.sail + core clauses):
 * unimplemented SPR -> None()/false; callers decide no-op vs exception. */
function clause read_spr(_) = None()
function clause write_spr(_, _) = false

end read_spr
end write_spr

$endif
