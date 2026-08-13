/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_assembly.sail — the textual form of every architecture-common
 * instruction: `assembly` is a scattered MAPPING, so one clause per
 * instruction defines both a disassembler and an assembler.
 *
 * Only the disassembler runs in the C emulator.  Sail marks the backwards
 * (string -> ast) direction of a string mapping non-executable, so calling
 * `assembly_backwards` from the model would fail to compile for C; the
 * assembler direction exists for the prover backends and for tooling built
 * on the Sail definition.  `step()` uses the forwards direction to label
 * each line of the -v 0x1 trace.
 *
 * SYNTAX.  Close to what `powerpc-linux-gnu-objdump -d` prints, so that a
 * trace can be read next to a disassembly listing: mnemonic, one space,
 * comma-separated operands, memory operands as `d(rA)`.  Immediates are
 * hexadecimal (hex_bits) rather than decimal, which keeps masks and shift
 * counts readable and makes the backwards direction unambiguous.
 *
 * Two conventions are the model's own rather than the assembler's:
 *
 *  - a field the 601 DECODES BUT IGNORES still has to appear in the text,
 *    because a mapping must be able to reconstruct the ast from it.  Where
 *    there is no real mnemonic for the resulting invalid form, the bit
 *    becomes a suffix (`mcrfl` for mcrf with LK set) or an extra operand
 *    (cmp's L bit, sc's low half-word).  Those spellings do not assemble.
 *  - an unrecognized word disassembles as `.long 0x...`, which is what one
 *    would have to write to reproduce it.
 *
 * Core-specific instructions are in the core's own assembly file, so that a
 * core which does not implement them contributes no clause.
 */

$ifndef _PPC_ASSEMBLY
$define _PPC_ASSEMBLY

$include <hex_bits.sail>
$include <mapping.sail>

/* --- Operand spellings -------------------------------------------------- */

/* Comma with no space after it, unlike the library's sep(), which prints
 * ", " — a trace line is easier to scan when the operands are tight. */
mapping sep_c : unit <-> string = { () <-> opt_spc() ^ "," ^ opt_spc() }

mapping reg_name : ridx <-> string = {
  0b00000 <-> "r0",   0b00001 <-> "r1",   0b00010 <-> "r2",   0b00011 <-> "r3",
  0b00100 <-> "r4",   0b00101 <-> "r5",   0b00110 <-> "r6",   0b00111 <-> "r7",
  0b01000 <-> "r8",   0b01001 <-> "r9",   0b01010 <-> "r10",  0b01011 <-> "r11",
  0b01100 <-> "r12",  0b01101 <-> "r13",  0b01110 <-> "r14",  0b01111 <-> "r15",
  0b10000 <-> "r16",  0b10001 <-> "r17",  0b10010 <-> "r18",  0b10011 <-> "r19",
  0b10100 <-> "r20",  0b10101 <-> "r21",  0b10110 <-> "r22",  0b10111 <-> "r23",
  0b11000 <-> "r24",  0b11001 <-> "r25",  0b11010 <-> "r26",  0b11011 <-> "r27",
  0b11100 <-> "r28",  0b11101 <-> "r29",  0b11110 <-> "r30",  0b11111 <-> "r31"
}

mapping fpr_name : fridx <-> string = {
  0b00000 <-> "f0",   0b00001 <-> "f1",   0b00010 <-> "f2",   0b00011 <-> "f3",
  0b00100 <-> "f4",   0b00101 <-> "f5",   0b00110 <-> "f6",   0b00111 <-> "f7",
  0b01000 <-> "f8",   0b01001 <-> "f9",   0b01010 <-> "f10",  0b01011 <-> "f11",
  0b01100 <-> "f12",  0b01101 <-> "f13",  0b01110 <-> "f14",  0b01111 <-> "f15",
  0b10000 <-> "f16",  0b10001 <-> "f17",  0b10010 <-> "f18",  0b10011 <-> "f19",
  0b10100 <-> "f20",  0b10101 <-> "f21",  0b10110 <-> "f22",  0b10111 <-> "f23",
  0b11000 <-> "f24",  0b11001 <-> "f25",  0b11010 <-> "f26",  0b11011 <-> "f27",
  0b11100 <-> "f28",  0b11101 <-> "f29",  0b11110 <-> "f30",  0b11111 <-> "f31"
}

mapping crf_name : cridx <-> string = {
  0b000 <-> "cr0", 0b001 <-> "cr1", 0b010 <-> "cr2", 0b011 <-> "cr3",
  0b100 <-> "cr4", 0b101 <-> "cr5", 0b110 <-> "cr6", 0b111 <-> "cr7"
}

/* A single bit as a bare digit, for the operands that are neither registers
 * nor immediates (cmp's L, and the branch hint bits inside BO). */
mapping bit_digit : bits(1) <-> string = { 0b0 <-> "0", 0b1 <-> "1" }

/* --- Mnemonic suffixes -------------------------------------------------- */

/* Rc, OE and the branch AA/LK bits, in the order they appear in a mnemonic:
 * `addo.`, `bcla`. */
mapping rc_dot : bits(1) <-> string = { 0b0 <-> "",  0b1 <-> "." }
mapping oe_mn  : bits(1) <-> string = { 0b0 <-> "",  0b1 <-> "o" }
mapping aa_mn  : bits(1) <-> string = { 0b0 <-> "",  0b1 <-> "a" }
mapping lk_mn  : bits(1) <-> string = { 0b0 <-> "",  0b1 <-> "l" }

/* The ast flags that select a mnemonic rather than an operand. */
mapping u_mn : bool <-> string = { false <-> "",  true <-> "u" }
mapping s_mn : bool <-> string = { false <-> "",  true <-> "s" }
mapping z_mn : bool <-> string = { false <-> "",  true <-> "z" }

/* --- Integer arithmetic (ppc_insts_int.sail) ---------------------------- */

mapping clause assembly = ADDI(rD, rA, simm) <->
  "addi" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ hex_bits_16(simm)

mapping clause assembly = ADDIS(rD, rA, simm) <->
  "addis" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ hex_bits_16(simm)

mapping clause assembly = ADDIC(rD, rA, simm) <->
  "addic" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ hex_bits_16(simm)

mapping clause assembly = ADDIC_DOT(rD, rA, simm) <->
  "addic." ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ hex_bits_16(simm)

mapping clause assembly = SUBFIC(rD, rA, simm) <->
  "subfic" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ hex_bits_16(simm)

mapping clause assembly = ADD(rD, rA, rB, oe, rc) <->
  "add" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = SUBF(rD, rA, rB, oe, rc) <->
  "subf" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = ADDC(rD, rA, rB, oe, rc) <->
  "addc" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = SUBFC(rD, rA, rB, oe, rc) <->
  "subfc" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = ADDE(rD, rA, rB, oe, rc) <->
  "adde" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = SUBFE(rD, rA, rB, oe, rc) <->
  "subfe" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = ADDME(rD, rA, oe, rc) <->
  "addme" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA)

mapping clause assembly = SUBFME(rD, rA, oe, rc) <->
  "subfme" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA)

mapping clause assembly = ADDZE(rD, rA, oe, rc) <->
  "addze" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA)

mapping clause assembly = SUBFZE(rD, rA, oe, rc) <->
  "subfze" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA)

mapping clause assembly = NEG(rD, rA, oe, rc) <->
  "neg" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA)

mapping clause assembly = MULLI(rD, rA, simm) <->
  "mulli" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ hex_bits_16(simm)

mapping clause assembly = MULLW(rD, rA, rB, oe, rc) <->
  "mullw" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = MULHW(rD, rA, rB, rc) <->
  "mulhw" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = MULHWU(rD, rA, rB, rc) <->
  "mulhwu" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = DIVW(rD, rA, rB, oe, rc) <->
  "divw" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = DIVWU(rD, rA, rB, oe, rc) <->
  "divwu" ^ oe_mn(oe) ^ rc_dot(rc) ^ spc()
  ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

/* The compares carry the L bit the 601 ignores, so it is printed: the
 * operand order is the manual's own, crfD,L,rA,rB. */
mapping clause assembly = CMP(crfd, l, rA, rB) <->
  "cmp" ^ spc() ^ crf_name(crfd) ^ sep_c() ^ bit_digit(l) ^ sep_c()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = CMPL(crfd, l, rA, rB) <->
  "cmpl" ^ spc() ^ crf_name(crfd) ^ sep_c() ^ bit_digit(l) ^ sep_c()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = CMPI(crfd, l, rA, simm) <->
  "cmpi" ^ spc() ^ crf_name(crfd) ^ sep_c() ^ bit_digit(l) ^ sep_c()
  ^ reg_name(rA) ^ sep_c() ^ hex_bits_16(simm)

mapping clause assembly = CMPLI(crfd, l, rA, uimm) <->
  "cmpli" ^ spc() ^ crf_name(crfd) ^ sep_c() ^ bit_digit(l) ^ sep_c()
  ^ reg_name(rA) ^ sep_c() ^ hex_bits_16(uimm)

/* --- Integer logical, rotate and shift ---------------------------------- */

/* The X-form logicals name the source first and the destination second, as
 * the encoding does. */
mapping clause assembly = ORI(rS, rA, uimm) <->
  "ori" ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(uimm)

mapping clause assembly = ORIS(rS, rA, uimm) <->
  "oris" ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(uimm)

mapping clause assembly = XORI(rS, rA, uimm) <->
  "xori" ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(uimm)

mapping clause assembly = XORIS(rS, rA, uimm) <->
  "xoris" ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(uimm)

mapping clause assembly = ANDI_DOT(rS, rA, uimm) <->
  "andi." ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(uimm)

mapping clause assembly = ANDIS_DOT(rS, rA, uimm) <->
  "andis." ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(uimm)

mapping clause assembly = AND(rS, rA, rB, rc) <->
  "and" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = OR(rS, rA, rB, rc) <->
  "or" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = XOR(rS, rA, rB, rc) <->
  "xor" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = NAND(rS, rA, rB, rc) <->
  "nand" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = NOR(rS, rA, rB, rc) <->
  "nor" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = EQV(rS, rA, rB, rc) <->
  "eqv" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = ANDC(rS, rA, rB, rc) <->
  "andc" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = ORC(rS, rA, rB, rc) <->
  "orc" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = EXTSB(rS, rA, rc) <->
  "extsb" ^ rc_dot(rc) ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS)

mapping clause assembly = EXTSH(rS, rA, rc) <->
  "extsh" ^ rc_dot(rc) ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS)

mapping clause assembly = CNTLZW(rS, rA, rc) <->
  "cntlzw" ^ rc_dot(rc) ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS)

mapping clause assembly = RLWINM(rS, rA, sh, mb, me, rc) <->
  "rlwinm" ^ rc_dot(rc) ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS)
  ^ sep_c() ^ hex_bits_5(sh) ^ sep_c() ^ hex_bits_5(mb) ^ sep_c() ^ hex_bits_5(me)

mapping clause assembly = RLWNM(rS, rA, rB, mb, me, rc) <->
  "rlwnm" ^ rc_dot(rc) ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS)
  ^ sep_c() ^ reg_name(rB) ^ sep_c() ^ hex_bits_5(mb) ^ sep_c() ^ hex_bits_5(me)

mapping clause assembly = RLWIMI(rS, rA, sh, mb, me, rc) <->
  "rlwimi" ^ rc_dot(rc) ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rS)
  ^ sep_c() ^ hex_bits_5(sh) ^ sep_c() ^ hex_bits_5(mb) ^ sep_c() ^ hex_bits_5(me)

mapping clause assembly = SLW(rS, rA, rB, rc) <->
  "slw" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = SRW(rS, rA, rB, rc) <->
  "srw" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = SRAW(rS, rA, rB, rc) <->
  "sraw" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = SRAWI(rS, rA, sh, rc) <->
  "srawi" ^ rc_dot(rc) ^ spc()
  ^ reg_name(rA) ^ sep_c() ^ reg_name(rS) ^ sep_c() ^ hex_bits_5(sh)

mapping clause assembly = TW(tofld, rA, rB) <->
  "tw" ^ spc() ^ hex_bits_5(tofld) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = TWI(tofld, rA, simm) <->
  "twi" ^ spc() ^ hex_bits_5(tofld) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ hex_bits_16(simm)

/* --- Integer loads and stores (ppc_insts_loadstore.sail) ---------------- */

/* D-form memory operands print as d(rA), as the assembler writes them. */
mapping clause assembly = LBZ(rD, rA, d) <->
  "lbz" ^ spc() ^ reg_name(rD) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = LBZU(rD, rA, d) <->
  "lbzu" ^ spc() ^ reg_name(rD) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = LHZ(rD, rA, d) <->
  "lhz" ^ spc() ^ reg_name(rD) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = LHZU(rD, rA, d) <->
  "lhzu" ^ spc() ^ reg_name(rD) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = LHA(rD, rA, d) <->
  "lha" ^ spc() ^ reg_name(rD) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = LHAU(rD, rA, d) <->
  "lhau" ^ spc() ^ reg_name(rD) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = LWZ(rD, rA, d) <->
  "lwz" ^ spc() ^ reg_name(rD) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = LWZU(rD, rA, d) <->
  "lwzu" ^ spc() ^ reg_name(rD) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = STB(rS, rA, d) <->
  "stb" ^ spc() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = STBU(rS, rA, d) <->
  "stbu" ^ spc() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = STH(rS, rA, d) <->
  "sth" ^ spc() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = STHU(rS, rA, d) <->
  "sthu" ^ spc() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = STW(rS, rA, d) <->
  "stw" ^ spc() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = STWU(rS, rA, d) <->
  "stwu" ^ spc() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = LMW(rD, rA, d) <->
  "lmw" ^ spc() ^ reg_name(rD) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = STMW(rS, rA, d) <->
  "stmw" ^ spc() ^ reg_name(rS) ^ sep_c() ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

/* X-form: the index register is an operand like any other. */
mapping clause assembly = LBZX(rD, rA, rB) <->
  "lbzx" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = LBZUX(rD, rA, rB) <->
  "lbzux" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = LHZX(rD, rA, rB) <->
  "lhzx" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = LHZUX(rD, rA, rB) <->
  "lhzux" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = LHAX(rD, rA, rB) <->
  "lhax" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = LHAUX(rD, rA, rB) <->
  "lhaux" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = LWZX(rD, rA, rB) <->
  "lwzx" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = LWZUX(rD, rA, rB) <->
  "lwzux" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = STBX(rS, rA, rB) <->
  "stbx" ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = STBUX(rS, rA, rB) <->
  "stbux" ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = STHX(rS, rA, rB) <->
  "sthx" ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = STHUX(rS, rA, rB) <->
  "sthux" ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = STWX(rS, rA, rB) <->
  "stwx" ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = STWUX(rS, rA, rB) <->
  "stwux" ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = LHBRX(rD, rA, rB) <->
  "lhbrx" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = LWBRX(rD, rA, rB) <->
  "lwbrx" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = STHBRX(rS, rA, rB) <->
  "sthbrx" ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = STWBRX(rS, rA, rB) <->
  "stwbrx" ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = LSWI(rD, rA, nb) <->
  "lswi" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ hex_bits_5(nb)

mapping clause assembly = STSWI(rS, rA, nb) <->
  "stswi" ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ hex_bits_5(nb)

mapping clause assembly = LSWX(rD, rA, rB) <->
  "lswx" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = STSWX(rS, rA, rB) <->
  "stswx" ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

/* --- Branches and condition-register logicals (ppc_insts_branch.sail) --- */

/* The AA and LK bits are suffixes in the order they appear in a mnemonic:
 * b, ba, bl, bla. */
mapping clause assembly = B(li, aa, lk) <->
  "b" ^ lk_mn(lk) ^ aa_mn(aa) ^ spc() ^ hex_bits_24(li)

mapping clause assembly = BC(bo, bi, bd, aa, lk) <->
  "bc" ^ lk_mn(lk) ^ aa_mn(aa) ^ spc()
  ^ hex_bits_5(bo) ^ sep_c() ^ hex_bits_5(bi) ^ sep_c() ^ hex_bits_14(bd)

mapping clause assembly = BCLR(bo, bi, lk) <->
  "bclr" ^ lk_mn(lk) ^ spc() ^ hex_bits_5(bo) ^ sep_c() ^ hex_bits_5(bi)

mapping clause assembly = BCCTR(bo, bi, lk) <->
  "bcctr" ^ lk_mn(lk) ^ spc() ^ hex_bits_5(bo) ^ sep_c() ^ hex_bits_5(bi)

mapping clause assembly = CRAND(crbd, crba, crbb) <->
  "crand" ^ spc() ^ hex_bits_5(crbd) ^ sep_c() ^ hex_bits_5(crba) ^ sep_c() ^ hex_bits_5(crbb)

mapping clause assembly = CROR(crbd, crba, crbb) <->
  "cror" ^ spc() ^ hex_bits_5(crbd) ^ sep_c() ^ hex_bits_5(crba) ^ sep_c() ^ hex_bits_5(crbb)

mapping clause assembly = CRXOR(crbd, crba, crbb) <->
  "crxor" ^ spc() ^ hex_bits_5(crbd) ^ sep_c() ^ hex_bits_5(crba) ^ sep_c() ^ hex_bits_5(crbb)

mapping clause assembly = CRNAND(crbd, crba, crbb) <->
  "crnand" ^ spc() ^ hex_bits_5(crbd) ^ sep_c() ^ hex_bits_5(crba) ^ sep_c() ^ hex_bits_5(crbb)

mapping clause assembly = CRNOR(crbd, crba, crbb) <->
  "crnor" ^ spc() ^ hex_bits_5(crbd) ^ sep_c() ^ hex_bits_5(crba) ^ sep_c() ^ hex_bits_5(crbb)

mapping clause assembly = CREQV(crbd, crba, crbb) <->
  "creqv" ^ spc() ^ hex_bits_5(crbd) ^ sep_c() ^ hex_bits_5(crba) ^ sep_c() ^ hex_bits_5(crbb)

mapping clause assembly = CRANDC(crbd, crba, crbb) <->
  "crandc" ^ spc() ^ hex_bits_5(crbd) ^ sep_c() ^ hex_bits_5(crba) ^ sep_c() ^ hex_bits_5(crbb)

mapping clause assembly = CRORC(crbd, crba, crbb) <->
  "crorc" ^ spc() ^ hex_bits_5(crbd) ^ sep_c() ^ hex_bits_5(crba) ^ sep_c() ^ hex_bits_5(crbb)

/* mcrf's LK bit is an invalid form the 601 executes and ignores (ch. 10 mcrf
 * page — see ppc_insts_branch.sail), and
 * it has no assembler spelling; the suffix marks it. */
mapping clause assembly = MCRF(crfd, crfs, lk) <->
  "mcrf" ^ lk_mn(lk) ^ spc() ^ crf_name(crfd) ^ sep_c() ^ crf_name(crfs)

/* --- System and processor control (ppc_insts_system.sail) --------------- */

mapping clause assembly = MFSPR(rD, spr) <->
  "mfspr" ^ spc() ^ reg_name(rD) ^ sep_c() ^ hex_bits_10(spr)

mapping clause assembly = MTSPR(rS, spr) <->
  "mtspr" ^ spc() ^ hex_bits_10(spr) ^ sep_c() ^ reg_name(rS)

mapping clause assembly = MFCR(rD) <-> "mfcr" ^ spc() ^ reg_name(rD)

mapping clause assembly = MTCRF(rS, crm) <->
  "mtcrf" ^ spc() ^ hex_bits_8(crm) ^ sep_c() ^ reg_name(rS)

mapping clause assembly = MCRXR(crfd) <-> "mcrxr" ^ spc() ^ crf_name(crfd)

mapping clause assembly = MFMSR(rD) <-> "mfmsr" ^ spc() ^ reg_name(rD)

mapping clause assembly = MTMSR(rS) <-> "mtmsr" ^ spc() ^ reg_name(rS)

mapping clause assembly = RFI() <-> "rfi"

mapping clause assembly = MTSR(rS, sr) <->
  "mtsr" ^ spc() ^ hex_bits_4(sr) ^ sep_c() ^ reg_name(rS)

mapping clause assembly = MFSR(rD, sr) <->
  "mfsr" ^ spc() ^ reg_name(rD) ^ sep_c() ^ hex_bits_4(sr)

mapping clause assembly = MTSRIN(rS, rB) <->
  "mtsrin" ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = MFSRIN(rD, rB) <->
  "mfsrin" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = TLBIE(rB) <-> "tlbie" ^ spc() ^ reg_name(rB)

mapping clause assembly = ECIWX(rD, rA, rB) <->
  "eciwx" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = ECOWX(rS, rA, rB) <->
  "ecowx" ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

/* sc carries the whole low half of its word, because three of those bits are
 * 601 deviations (ch. 10 sc page) and SRR1 keeps them; the assembler writes `sc`
 * and leaves them zero. */
mapping clause assembly = SC(imm) <-> "sc" ^ spc() ^ hex_bits_16(imm)

/* --- Cache control and synchronization (ppc_insts_cache.sail) ----------- */

mapping clause assembly = SYNC() <-> "sync"
mapping clause assembly = ISYNC() <-> "isync"
mapping clause assembly = EIEIO() <-> "eieio"

mapping clause assembly = LWARX(rD, rA, rB) <->
  "lwarx" ^ spc() ^ reg_name(rD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = STWCX(rS, rA, rB) <->
  "stwcx." ^ spc() ^ reg_name(rS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = DCBT(rA, rB) <->
  "dcbt" ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = DCBTST(rA, rB) <->
  "dcbtst" ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = ICBI(rA, rB) <->
  "icbi" ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = DCBST(rA, rB) <->
  "dcbst" ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = DCBF(rA, rB) <->
  "dcbf" ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = DCBI(rA, rB) <->
  "dcbi" ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = DCBZ(rA, rB) <->
  "dcbz" ^ spc() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

/* --- Floating point (ppc_insts_fp.sail) --------------------------------- */

/* The update bit is part of the mnemonic for loads and stores, and the
 * precision bit for the arithmetic: lfs/lfsu/lfsx/lfsux, fadd/fadds. */
mapping clause assembly = LFS(frD, rA, d, update) <->
  "lfs" ^ u_mn(update) ^ spc() ^ fpr_name(frD) ^ sep_c()
  ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = LFD(frD, rA, d, update) <->
  "lfd" ^ u_mn(update) ^ spc() ^ fpr_name(frD) ^ sep_c()
  ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = STFS(frS, rA, d, update) <->
  "stfs" ^ u_mn(update) ^ spc() ^ fpr_name(frS) ^ sep_c()
  ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = STFD(frS, rA, d, update) <->
  "stfd" ^ u_mn(update) ^ spc() ^ fpr_name(frS) ^ sep_c()
  ^ hex_bits_16(d) ^ "(" ^ reg_name(rA) ^ ")"

mapping clause assembly = LFSX(frD, rA, rB, update) <->
  "lfs" ^ u_mn(update) ^ "x" ^ spc()
  ^ fpr_name(frD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = LFDX(frD, rA, rB, update) <->
  "lfd" ^ u_mn(update) ^ "x" ^ spc()
  ^ fpr_name(frD) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = STFSX(frS, rA, rB, update) <->
  "stfs" ^ u_mn(update) ^ "x" ^ spc()
  ^ fpr_name(frS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = STFDX(frS, rA, rB, update) <->
  "stfd" ^ u_mn(update) ^ "x" ^ spc()
  ^ fpr_name(frS) ^ sep_c() ^ reg_name(rA) ^ sep_c() ^ reg_name(rB)

mapping clause assembly = FMR(frD, frB, rc) <->
  "fmr" ^ rc_dot(rc) ^ spc() ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = FNEG(frD, frB, rc) <->
  "fneg" ^ rc_dot(rc) ^ spc() ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = FABS(frD, frB, rc) <->
  "fabs" ^ rc_dot(rc) ^ spc() ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = FNABS(frD, frB, rc) <->
  "fnabs" ^ rc_dot(rc) ^ spc() ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = FADD(frD, frA, frB, single, rc) <->
  "fadd" ^ s_mn(single) ^ rc_dot(rc) ^ spc()
  ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frA) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = FSUB(frD, frA, frB, single, rc) <->
  "fsub" ^ s_mn(single) ^ rc_dot(rc) ^ spc()
  ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frA) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = FMUL(frD, frA, frC, single, rc) <->
  "fmul" ^ s_mn(single) ^ rc_dot(rc) ^ spc()
  ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frA) ^ sep_c() ^ fpr_name(frC)

mapping clause assembly = FDIV(frD, frA, frB, single, rc) <->
  "fdiv" ^ s_mn(single) ^ rc_dot(rc) ^ spc()
  ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frA) ^ sep_c() ^ fpr_name(frB)

/* The four multiply-add mnemonics, selected by the two flags the ast
 * carries; the operand order is frD,frA,frC,frB throughout. */
mapping fma_mn : (bool, bool) <-> string = {
  (false, false) <-> "fmadd",
  (true,  false) <-> "fmsub",
  (false, true)  <-> "fnmadd",
  (true,  true)  <-> "fnmsub"
}

mapping clause assembly = FMADD(frD, frA, frC, frB, subtract, negate, single, rc) <->
  fma_mn(subtract, negate) ^ s_mn(single) ^ rc_dot(rc) ^ spc()
  ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frA) ^ sep_c()
  ^ fpr_name(frC) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = FRSP(frD, frB, rc) <->
  "frsp" ^ rc_dot(rc) ^ spc() ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = FCTIW(frD, frB, toward_zero, rc) <->
  "fctiw" ^ z_mn(toward_zero) ^ rc_dot(rc) ^ spc()
  ^ fpr_name(frD) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = FCMPU(crfd, frA, frB) <->
  "fcmpu" ^ spc() ^ crf_name(crfd) ^ sep_c() ^ fpr_name(frA) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = FCMPO(crfd, frA, frB) <->
  "fcmpo" ^ spc() ^ crf_name(crfd) ^ sep_c() ^ fpr_name(frA) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = MFFS(frD, rc) <->
  "mffs" ^ rc_dot(rc) ^ spc() ^ fpr_name(frD)

mapping clause assembly = MCRFS(crfd, crfs) <->
  "mcrfs" ^ spc() ^ crf_name(crfd) ^ sep_c() ^ crf_name(crfs)

mapping clause assembly = MTFSFI(crfd, imm, rc) <->
  "mtfsfi" ^ rc_dot(rc) ^ spc() ^ crf_name(crfd) ^ sep_c() ^ hex_bits_4(imm)

mapping clause assembly = MTFSF(fm, frB, rc) <->
  "mtfsf" ^ rc_dot(rc) ^ spc() ^ hex_bits_8(fm) ^ sep_c() ^ fpr_name(frB)

mapping clause assembly = MTFSB0(crbd, rc) <->
  "mtfsb0" ^ rc_dot(rc) ^ spc() ^ hex_bits_5(crbd)

mapping clause assembly = MTFSB1(crbd, rc) <->
  "mtfsb1" ^ rc_dot(rc) ^ spc() ^ hex_bits_5(crbd)

$endif
