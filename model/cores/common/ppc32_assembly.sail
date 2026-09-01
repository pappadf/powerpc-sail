/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc32_assembly.sail — disassembly for the instructions in ppc32_insts.sail.
 * Kept in its own file for the same reason ppc_assembly.sail is: the mapping
 * is opened there and every clause must sit between that and
 * ppc_insts_end.sail. */

$ifndef _PPC32_ASSEMBLY
$define _PPC32_ASSEMBLY

mapping clause assembly = MFTB(rD, tbr) <->
  "mftb" ^ spc() ^ reg_name(rD) ^ sep_c() ^ hex_bits_10(tbr)

mapping clause assembly = TLBSYNC() <-> "tlbsync"

mapping clause assembly = STFIWX(frS, rA, rB) <->
  "stfiwx" ^ spc() ^ fpr_name(frS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = FSEL(frD, frA, frC, frB, rc) <->
  "fsel" ^ rc_dot(rc) ^ spc() ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frA)
         ^ sep_c() ^ fpr_name(frC) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = FRES(frD, frB, rc) <->
  "fres" ^ rc_dot(rc) ^ spc() ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frB)

$endif
