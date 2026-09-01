/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p603_insts.sail — the two 603-specific instructions, tlbld and tlbli
 * (MPC603EUM §2.3.8, and their chapter-2 instruction pages).
 *
 * "This is a supervisor-level instruction; it is also a MPC603e-specific
 * instruction, and not part of the PowerPC instruction set" — so they are
 * absent from every other core in this model and their opcodes correctly
 * decode as illegal there. */

$ifndef _P603_INSTS
$define _P603_INSTS

/* tlbld rB (X-form, XO=978) and tlbli rB (X-form, XO=1010).
 *
 * Each takes the effective address in rB and installs a TLB entry built from
 * the compare and physical-address registers: tlbld merges DCMP with RPA into
 * the data TLB, tlbli merges ICMP with RPA into the instruction TLB, in both
 * cases into the entry selected by EA[15:19] and SRR1[WAY].
 *
 * NO TLB IS MODELLED, so both are privileged no-ops here.
 *
 * That is exactly right rather than a stub, given the rest of the model.
 * ppc_mmu.sail walks the page table on every access and never caches the
 * result, which is observationally equivalent to a TLB that is always
 * coherent with memory; against such a TLB, "install this entry" is a
 * no-operation, because the entry is already what a lookup would find.  What
 * IS lost is the exception that would have driven a handler to execute one of
 * these in the first place — see core_exception_vector in p603_core.sail,
 * which is where that divergence belongs and is argued.
 *
 * Neither instruction alters any register ("Other registers altered: None"),
 * so there is nothing else to leave behind. */
union clause ast = TLBLD : ridx

mapping clause encdec =
  TLBLD(rB) <-> 0b011111 @ 0b00000 @ 0b00000 @ rB : ridx @ 0b1111010010 @ 0b0

function clause execute(TLBLD(_rB)) =
  if in_user_mode() then program_exception(Prog_Privileged)
  else COMPLETED

union clause ast = TLBLI : ridx

mapping clause encdec =
  TLBLI(rB) <-> 0b011111 @ 0b00000 @ 0b00000 @ rB : ridx @ 0b1111110010 @ 0b0

function clause execute(TLBLI(_rB)) =
  if in_user_mode() then program_exception(Prog_Privileged)
  else COMPLETED

$endif
