/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p601_assembly.sail — the textual form of the 28 POWER-architecture
 * holdovers in p601_insts_power.sail.  They live here rather than in
 * ppc_assembly.sail for the same reason their semantics live in the core
 * directory: a core that does not decode them contributes no clause, and its
 * disassembler will not name them either.
 *
 * The GNU assembler accepts every mnemonic below only with `.machine "601"`
 * (and has none for `clcs.`), so a trace line and an objdump listing agree
 * only when the listing was produced that way.  See ppc_assembly.sail for
 * the syntax conventions. */

$ifndef _P601_ASSEMBLY
$define _P601_ASSEMBLY

/* --- Arithmetic (Table 3-2) --------------------------------------------- */

mapping clause assembly = P601_ABS(rD, rA, oe, rc) <->
  "abs" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA)

mapping clause assembly = P601_NABS(rD, rA, oe, rc) <->
  "nabs" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA)

mapping clause assembly = P601_DOZ(rD, rA, rB, oe, rc) <->
  "doz" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_DOZI(rD, rA, simm) <->
  "dozi" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ hex_bits_16(simm)

mapping clause assembly = P601_MUL(rD, rA, rB, oe, rc) <->
  "mul" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_DIV(rD, rA, rB, oe, rc) <->
  "div" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_DIVS(rD, rA, rB, oe, rc) <->
  "divs" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

/* --- Rotate and mask (Table 3-8) ---------------------------------------- */

mapping clause assembly = P601_RLMI(rS, rA, rB, mb, me, rc) <->
  "rlmi" ^ rc_dot(rc) ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS)
  ^ sep_c() ^ reg_name(rB) ^ sep_c() ^ hex_bits_5(mb) ^ sep_c() ^ hex_bits_5(me)

mapping clause assembly = P601_RRIB(rS, rA, rB, rc) <->
  "rrib" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_MASKG(rS, rA, rB, rc) <->
  "maskg" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_MASKIR(rS, rA, rB, rc) <->
  "maskir" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

/* --- Shifts with MQ (Table 3-9) ----------------------------------------- */

mapping clause assembly = P601_SLE(rS, rA, rB, rc) <->
  "sle" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_SRE(rS, rA, rB, rc) <->
  "sre" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_SLEQ(rS, rA, rB, rc) <->
  "sleq" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_SREQ(rS, rA, rB, rc) <->
  "sreq" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_SLQ(rS, rA, rB, rc) <->
  "slq" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_SRQ(rS, rA, rB, rc) <->
  "srq" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_SLLQ(rS, rA, rB, rc) <->
  "sllq" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_SRLQ(rS, rA, rB, rc) <->
  "srlq" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_SRAQ(rS, rA, rB, rc) <->
  "sraq" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_SREA(rS, rA, rB, rc) <->
  "srea" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_SLIQ(rS, rA, sh, rc) <->
  "sliq" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ hex_bits_5(sh)

mapping clause assembly = P601_SRIQ(rS, rA, sh, rc) <->
  "sriq" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ hex_bits_5(sh)

mapping clause assembly = P601_SLLIQ(rS, rA, sh, rc) <->
  "slliq" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ hex_bits_5(sh)

mapping clause assembly = P601_SRLIQ(rS, rA, sh, rc) <->
  "srliq" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ hex_bits_5(sh)

mapping clause assembly = P601_SRAIQ(rS, rA, sh, rc) <->
  "sraiq" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ hex_bits_5(sh)

/* --- String compare and cache line size --------------------------------- */

mapping clause assembly = P601_LSCBX(rD, rA, rB, rc) <->
  "lscbx" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = P601_CLCS(rD, rA, rc) <->
  "clcs" ^ rc_dot(rc) ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA)

$endif
