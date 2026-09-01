/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p603_assembly.sail — disassembly for the instructions in p603_insts.sail. */

$ifndef _P603_ASSEMBLY
$define _P603_ASSEMBLY

mapping clause assembly = TLBLD(rB) <-> "tlbld" ^ spc() ^ reg_name(rB)
mapping clause assembly = TLBLI(rB) <-> "tlbli" ^ spc() ^ reg_name(rB)

$endif
