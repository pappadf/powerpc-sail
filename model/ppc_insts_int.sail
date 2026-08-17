/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_insts_int.sail — integer arithmetic, compare, logical, rotate and
 * shift instructions (MPC601UM §3.3, ch. 10 for individual semantics).
 *
 * IMPLEMENTED:
 *   addi, addis, addic, addic., subfic          (D-form arithmetic)
 *   add[o][.] subf[o][.] addc[o][.] subfc[o][.] adde[o][.] subfe[o][.]
 *   addme[o][.] subfme[o][.] addze[o][.] subfze[o][.] neg[o][.]
 *   mulli mullw[o][.] mulhw[.] mulhwu[.] divw[o][.] divwu[o][.]
 *   cmp cmpi cmpl cmpli                         (Table 3-3)
 *   ori oris xori xoris andi. andis.            (Table 3-5, D-form logical)
 *   and[.] or[.] xor[.] nand[.] nor[.] eqv[.] andc[.] orc[.]
 *   extsb[.] extsh[.] cntlzw[.]                 (Table 3-5, X-form logical)
 *   rlwinm[.] rlwnm[.] rlwimi[.]                (Table 3-8, rotate)
 *   slw[.] srw[.] sraw[.] srawi[.]              (Table 3-9, shift)
 *   tw twi                                      (Table 3-34, trap)
 *
 * (601-only POWER instructions — doz, abs, mul, div, rlmi, sle, ... — live
 * in cores/p601/p601_insts_power.sail.)
 */

$ifndef _PPC_INSTS_INT
$define _PPC_INSTS_INT

/* "(rA|0)": D-form arithmetic instructions read 0, not GPR(0), when rA=0. */
val gpr_or_zero : ridx -> word
function gpr_or_zero(r) = if r == 0b00000 then zeros(32) else GPR(r)

/* --- addi rD,rA,SIMM : rD = (rA|0) + EXTS(SIMM) ------------------------- */

union clause ast = ADDI : (ridx, ridx, bits(16))

mapping clause encdec =
  ADDI(rD, rA, simm) <-> 0b001110 @ rD : ridx @ rA : ridx @ simm : bits(16)

function clause execute(ADDI(rD, rA, simm)) = {
  GPR(rD) = gpr_or_zero(rA) + exts(simm);
  COMPLETED
}

/* --- addis rD,rA,SIMM : rD = (rA|0) + (SIMM << 16) ---------------------- */

union clause ast = ADDIS : (ridx, ridx, bits(16))

mapping clause encdec =
  ADDIS(rD, rA, simm) <-> 0b001111 @ rD : ridx @ rA : ridx @ simm : bits(16)

function clause execute(ADDIS(rD, rA, simm)) = {
  GPR(rD) = gpr_or_zero(rA) + (simm @ 0x0000);
  COMPLETED
}

/* --- Shared add/subtract primitives ------------------------------------- */

/* Every integer add and subtract in the architecture is one 32-bit addition
 * of three inputs.  Subtract-from computes ¬(rA) + b + carry-in, which is
 * why subfc/subfe/subfze/subfme record a *carry* rather than a borrow.
 *
 * Returns (result, carry-out, signed-overflow):
 *  - carry-out is the carry out of the most significant bit (manual bit 0);
 *    that is what XER[CA] records.
 *  - signed overflow is the XER[OV] condition: the two addends agree in sign
 *    and the result disagrees (MPC601UM §2.2.5.2). */
val add_with_carry : (word, word, bits(1)) -> (word, bits(1), bits(1))
function add_with_carry(a, b, cin) = {
  let sum : bits(33) = sail_zero_extend(a, 33) + sail_zero_extend(b, 33)
                       + sail_zero_extend(cin, 33);
  let res = sum[31 .. 0];
  let ca = [sum[32]];
  let ov = bool_to_bits((a[31] == b[31]) & (a[31] != res[31]));
  (res, ca, ov)
}

/* Common result tail for the arithmetic instructions: write rD, then the
 * OE-gated XER[OV]/XER[SO] update and the Rc-gated CR0 update.  XER[SO] is
 * updated first because CR0[SO] is a copy of it (§2.2.5.2). */
val arith_result : (ridx, word, bits(1), bits(1), bits(1)) -> unit
function arith_result(rD, res, ov, oe, rc) = {
  if oe == 0b1 then {
    harness_note_write(hw_xer, hw_xer_ov);
    XER[OV] = ov;
    if ov == 0b1 then { harness_note_write(hw_xer, hw_xer_so); XER[SO] = 0b1 }
  };
  GPR(rD) = res;
  if rc == 0b1 then set_cr0(res)
}

/* rD = a + b + cin.  `ca` selects whether the instruction records the carry
 * (the "carrying"/"extended" forms do; add/subf/neg do not). */
val exec_add_sub : (ridx, word, word, bits(1), bool, bits(1), bits(1)) -> Completion
function exec_add_sub(rD, a, b, cin, ca, oe, rc) = {
  let (res, cout, ov) = add_with_carry(a, b, cin);
  if ca then { harness_note_write(hw_xer, hw_xer_ca); XER[CA] = cout };
  arith_result(rD, res, ov, oe, rc);
  COMPLETED
}

/* --- addic rD,rA,SIMM : rD = rA + EXTS(SIMM), sets XER[CA] -------------- */

/* NOTE these three read (rA), not (rA|0): only addi/addis/loads use "|0". */
union clause ast = ADDIC : (ridx, ridx, bits(16))

mapping clause encdec =
  ADDIC(rD, rA, simm) <-> 0b001100 @ rD : ridx @ rA : ridx @ simm : bits(16)

function clause execute(ADDIC(rD, rA, simm)) =
  exec_add_sub(rD, GPR(rA), exts(simm), 0b0, true, 0b0, 0b0)

/* --- addic. rD,rA,SIMM : as addic, and always updates CR0 --------------- */

union clause ast = ADDIC_DOT : (ridx, ridx, bits(16))

mapping clause encdec =
  ADDIC_DOT(rD, rA, simm) <-> 0b001101 @ rD : ridx @ rA : ridx @ simm : bits(16)

function clause execute(ADDIC_DOT(rD, rA, simm)) =
  exec_add_sub(rD, GPR(rA), exts(simm), 0b0, true, 0b0, 0b1)

/* --- subfic rD,rA,SIMM : rD = ¬rA + EXTS(SIMM) + 1, sets XER[CA] -------- */

union clause ast = SUBFIC : (ridx, ridx, bits(16))

mapping clause encdec =
  SUBFIC(rD, rA, simm) <-> 0b001000 @ rD : ridx @ rA : ridx @ simm : bits(16)

function clause execute(SUBFIC(rD, rA, simm)) =
  exec_add_sub(rD, not_vec(GPR(rA)), exts(simm), 0b1, true, 0b0, 0b0)

/* --- XO-form add/subtract family ---------------------------------------- */

/* All share the layout 31 | D | A | B | OE | XO(9) | Rc.  The two-operand
 * forms (addme, addze, subfme, subfze, neg) have a reserved 00000 B field.
 * INVALID-FORM: a nonzero reserved B field does not match these encodings
 * and therefore decodes to ILLEGAL today, whereas §5.4.7 requires invalid
 * forms to be boundedly undefined rather than trap: "instructions using an
 * invalid instruction form do not take a program exception".
 * TODO: reserved fields need one model-wide decision — every INVALID-FORM
 * note in the model diverges this same way, so they stand or fall together. */

union clause ast = ADD : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  ADD(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b100001010 @ rc : bits(1)

function clause execute(ADD(rD, rA, rB, oe, rc)) =
  exec_add_sub(rD, GPR(rA), GPR(rB), 0b0, false, oe, rc)

/* subf[o][.] rD,rA,rB (XO=40): rD = ¬rA + rB + 1 */
union clause ast = SUBF : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  SUBF(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b000101000 @ rc : bits(1)

function clause execute(SUBF(rD, rA, rB, oe, rc)) =
  exec_add_sub(rD, not_vec(GPR(rA)), GPR(rB), 0b1, false, oe, rc)

/* addc[o][.] rD,rA,rB (XO=10): rD = rA + rB, records carry */
union clause ast = ADDC : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  ADDC(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b000001010 @ rc : bits(1)

function clause execute(ADDC(rD, rA, rB, oe, rc)) =
  exec_add_sub(rD, GPR(rA), GPR(rB), 0b0, true, oe, rc)

/* subfc[o][.] rD,rA,rB (XO=8): rD = ¬rA + rB + 1, records carry */
union clause ast = SUBFC : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  SUBFC(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b000001000 @ rc : bits(1)

function clause execute(SUBFC(rD, rA, rB, oe, rc)) =
  exec_add_sub(rD, not_vec(GPR(rA)), GPR(rB), 0b1, true, oe, rc)

/* adde[o][.] rD,rA,rB (XO=138): rD = rA + rB + XER[CA] */
union clause ast = ADDE : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  ADDE(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b010001010 @ rc : bits(1)

function clause execute(ADDE(rD, rA, rB, oe, rc)) =
  exec_add_sub(rD, GPR(rA), GPR(rB), XER[CA], true, oe, rc)

/* subfe[o][.] rD,rA,rB (XO=136): rD = ¬rA + rB + XER[CA] */
union clause ast = SUBFE : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  SUBFE(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b010001000 @ rc : bits(1)

function clause execute(SUBFE(rD, rA, rB, oe, rc)) =
  exec_add_sub(rD, not_vec(GPR(rA)), GPR(rB), XER[CA], true, oe, rc)

/* addme[o][.] rD,rA (XO=234): rD = rA + XER[CA] + 0xFFFF_FFFF */
union clause ast = ADDME : (ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  ADDME(rD, rA, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ 0b00000 @ oe : bits(1) @ 0b011101010 @ rc : bits(1)

function clause execute(ADDME(rD, rA, oe, rc)) =
  exec_add_sub(rD, GPR(rA), ones(32), XER[CA], true, oe, rc)

/* subfme[o][.] rD,rA (XO=232): rD = ¬rA + XER[CA] + 0xFFFF_FFFF */
union clause ast = SUBFME : (ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  SUBFME(rD, rA, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ 0b00000 @ oe : bits(1) @ 0b011101000 @ rc : bits(1)

function clause execute(SUBFME(rD, rA, oe, rc)) =
  exec_add_sub(rD, not_vec(GPR(rA)), ones(32), XER[CA], true, oe, rc)

/* addze[o][.] rD,rA (XO=202): rD = rA + XER[CA] */
union clause ast = ADDZE : (ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  ADDZE(rD, rA, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ 0b00000 @ oe : bits(1) @ 0b011001010 @ rc : bits(1)

function clause execute(ADDZE(rD, rA, oe, rc)) =
  exec_add_sub(rD, GPR(rA), zeros(32), XER[CA], true, oe, rc)

/* subfze[o][.] rD,rA (XO=200): rD = ¬rA + XER[CA] */
union clause ast = SUBFZE : (ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  SUBFZE(rD, rA, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ 0b00000 @ oe : bits(1) @ 0b011001000 @ rc : bits(1)

function clause execute(SUBFZE(rD, rA, oe, rc)) =
  exec_add_sub(rD, not_vec(GPR(rA)), zeros(32), XER[CA], true, oe, rc)

/* neg[o][.] rD,rA (XO=104): rD = ¬rA + 1.  neg of 0x8000_0000 returns
 * 0x8000_0000 and sets OV when OE=1 — which the generic signed-overflow
 * rule above already produces.  Does NOT record a carry. */
union clause ast = NEG : (ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  NEG(rD, rA, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ 0b00000 @ oe : bits(1) @ 0b001101000 @ rc : bits(1)

function clause execute(NEG(rD, rA, oe, rc)) =
  exec_add_sub(rD, not_vec(GPR(rA)), zeros(32), 0b1, false, oe, rc)

/* --- Multiply ----------------------------------------------------------- */

/* UNDEF: on the 601 all six multiply and divide instructions leave the MQ
 * register in an undefined state (MPC601UM Table 2-7).  The UNDEF policy is
 * "leave unchanged", so there is nothing for common code to do — and MQ is a
 * core register that common code must not touch anyway.
 *
 * Sail has no bitvector multiply or divide, so these go through the
 * arbitrary-precision integer operations and slice the result back down;
 * that also makes the 64-bit intermediate product exact by construction. */

/* mulli rD,rA,SIMM (opcode 7): rD = low 32 bits of rA * EXTS(SIMM).  The low
 * half is the same whether the operands are read as signed or unsigned. */
union clause ast = MULLI : (ridx, ridx, bits(16))

mapping clause encdec =
  MULLI(rD, rA, simm) <-> 0b000111 @ rD : ridx @ rA : ridx @ simm : bits(16)

function clause execute(MULLI(rD, rA, simm)) = {
  GPR(rD) = get_slice_int(32, signed(GPR(rA)) * signed(simm), 0);
  COMPLETED
}

/* mullw[o][.] rD,rA,rB (XO=235): low 32 bits of the 64-bit product. */
union clause ast = MULLW : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  MULLW(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b011101011 @ rc : bits(1)

function clause execute(MULLW(rD, rA, rB, oe, rc)) = {
  let prod = signed(GPR(rA)) * signed(GPR(rB));
  /* OE=1: OV records that the signed product does not fit in 32 bits. */
  let ov = bool_to_bits((prod < -2147483648) | (prod > 2147483647));
  arith_result(rD, get_slice_int(32, prod, 0), ov, oe, rc);
  COMPLETED
}

/* mulhw[.] rD,rA,rB (XO=75): high 32 bits of the signed 64-bit product.
 * There is no OE bit; manual bit 21 is reserved. */
union clause ast = MULHW : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  MULHW(rD, rA, rB, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0 @ 0b001001011 @ rc : bits(1)

function clause execute(MULHW(rD, rA, rB, rc)) = {
  let prod = signed(GPR(rA)) * signed(GPR(rB));
  arith_result(rD, get_slice_int(32, prod, 32), 0b0, 0b0, rc);
  COMPLETED
}

/* mulhwu[.] rD,rA,rB (XO=11): high 32 bits of the unsigned 64-bit product. */
union clause ast = MULHWU : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  MULHWU(rD, rA, rB, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0 @ 0b000001011 @ rc : bits(1)

function clause execute(MULHWU(rD, rA, rB, rc)) = {
  let prod = unsigned(GPR(rA)) * unsigned(GPR(rB));
  arith_result(rD, get_slice_int(32, prod, 32), 0b0, 0b0, rc);
  COMPLETED
}

/* --- Divide ------------------------------------------------------------- */

/* Both divides truncate toward zero (the remainder takes the sign of the
 * dividend), which is tdiv_int.
 *
 * UNDEF (ch. 10, divw/divwu pages): 0x8000_0000 / -1 and <anything> / 0
 * leave rD undefined, and with Rc=1 the CR0 LT/GT/EQ bits too; OV is set
 * when OE=1.  Under the UNDEF policy rD keeps its previous value, and CR0 —
 * which is computed from whatever rD ends up holding — then records that.
 * Only the OV/SO update is architecturally defined in these cases. */

union clause ast = DIVW : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  DIVW(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b111101011 @ rc : bits(1)

function clause execute(DIVW(rD, rA, rB, oe, rc)) = {
  let a = GPR(rA);
  let b = GPR(rB);
  let undef = (b == zeros(32)) | ((a == 0x80000000) & (b == ones(32)));
  let res = if undef then GPR(rD)
            else get_slice_int(32, tdiv_int(signed(a), signed(b)), 0);
  arith_result(rD, res, bool_to_bits(undef), oe, rc);
  COMPLETED
}

union clause ast = DIVWU : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  DIVWU(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b111001011 @ rc : bits(1)

function clause execute(DIVWU(rD, rA, rB, oe, rc)) = {
  let a = GPR(rA);
  let b = GPR(rB);
  let undef = b == zeros(32);
  let res = if undef then GPR(rD)
            else get_slice_int(32, tdiv_int(unsigned(a), unsigned(b)), 0);
  arith_result(rD, res, bool_to_bits(undef), oe, rc);
  COMPLETED
}

/* --- Compare ------------------------------------------------------------ */

/* All four compares write LT/GT/EQ plus a copy of XER[SO] into the CR field
 * named by crfD (ch. 10, cmp page: CR[4*crfD .. 4*crfD+3] <- c || XER[SO]).
 * Exactly one of LT/GT/EQ is set, so EQ is "neither of the others". */
val set_cr_cmp : (cridx, bool, bool) -> unit
function set_cr_cmp(crfd, lt, gt) = {
  let c : bits(3) = bool_to_bits(lt) @ bool_to_bits(gt) @ bool_to_bits(not_bool(lt | gt));
  CRfield(unsigned(crfd), c @ XER[SO])
}

/* INVALID-FORM: the L operand selects 64-bit operands, which a 32-bit
 * implementation does not have; the manual is explicit that "the state of
 * the L operand does not affect the operation of the 601", so all four
 * compares decode L and ignore it rather than treating L=1 as illegal. */

/* cmp crfD,L,rA,rB (X-form, XO=0): signed. */
union clause ast = CMP : (cridx, bits(1), ridx, ridx)

mapping clause encdec =
  CMP(crfd, l, rA, rB) <->
    0b011111 @ crfd : cridx @ 0b0 @ l : bits(1) @ rA : ridx @ rB : ridx
    @ 0b0000000000 @ 0b0

function clause execute(CMP(crfd, _, rA, rB)) = {
  let a = signed(GPR(rA));
  let b = signed(GPR(rB));
  set_cr_cmp(crfd, a < b, a > b);
  COMPLETED
}

/* cmpl crfD,L,rA,rB (X-form, XO=32): unsigned. */
union clause ast = CMPL : (cridx, bits(1), ridx, ridx)

mapping clause encdec =
  CMPL(crfd, l, rA, rB) <->
    0b011111 @ crfd : cridx @ 0b0 @ l : bits(1) @ rA : ridx @ rB : ridx
    @ 0b0000100000 @ 0b0

function clause execute(CMPL(crfd, _, rA, rB)) = {
  let a = unsigned(GPR(rA));
  let b = unsigned(GPR(rB));
  set_cr_cmp(crfd, a < b, a > b);
  COMPLETED
}

/* cmpi crfD,L,rA,SIMM (opcode 11): signed against a sign-extended immediate. */
union clause ast = CMPI : (cridx, bits(1), ridx, bits(16))

mapping clause encdec =
  CMPI(crfd, l, rA, simm) <->
    0b001011 @ crfd : cridx @ 0b0 @ l : bits(1) @ rA : ridx @ simm : bits(16)

function clause execute(CMPI(crfd, _, rA, simm)) = {
  let a = signed(GPR(rA));
  let b = signed(simm);
  set_cr_cmp(crfd, a < b, a > b);
  COMPLETED
}

/* cmpli crfD,L,rA,UIMM (opcode 10): unsigned against a zero-extended
 * immediate (note UIMM is NOT sign-extended, unlike cmpi's SIMM). */
union clause ast = CMPLI : (cridx, bits(1), ridx, bits(16))

mapping clause encdec =
  CMPLI(crfd, l, rA, uimm) <->
    0b001010 @ crfd : cridx @ 0b0 @ l : bits(1) @ rA : ridx @ uimm : bits(16)

function clause execute(CMPLI(crfd, _, rA, uimm)) = {
  let a = unsigned(GPR(rA));
  let b = unsigned(uimm);
  set_cr_cmp(crfd, a < b, a > b);
  COMPLETED
}

/* --- ori rA,rS,UIMM : rA = rS | EXTZ(UIMM) ------------------------------ */

/* NOTE encoding field order: D-form logical ops encode rS first, then rA. */
union clause ast = ORI : (ridx, ridx, bits(16))

mapping clause encdec =
  ORI(rS, rA, uimm) <-> 0b011000 @ rS : ridx @ rA : ridx @ uimm : bits(16)

function clause execute(ORI(rS, rA, uimm)) = {
  GPR(rA) = GPR(rS) | extz(uimm);
  COMPLETED
}

/* --- oris/xori/xoris: no CR0, no XER ------------------------------------ */

union clause ast = ORIS : (ridx, ridx, bits(16))

mapping clause encdec =
  ORIS(rS, rA, uimm) <-> 0b011001 @ rS : ridx @ rA : ridx @ uimm : bits(16)

function clause execute(ORIS(rS, rA, uimm)) = {
  GPR(rA) = GPR(rS) | (uimm @ 0x0000);
  COMPLETED
}

union clause ast = XORI : (ridx, ridx, bits(16))

mapping clause encdec =
  XORI(rS, rA, uimm) <-> 0b011010 @ rS : ridx @ rA : ridx @ uimm : bits(16)

function clause execute(XORI(rS, rA, uimm)) = {
  GPR(rA) = xor_vec(GPR(rS), extz(uimm));
  COMPLETED
}

union clause ast = XORIS : (ridx, ridx, bits(16))

mapping clause encdec =
  XORIS(rS, rA, uimm) <-> 0b011011 @ rS : ridx @ rA : ridx @ uimm : bits(16)

function clause execute(XORIS(rS, rA, uimm)) = {
  GPR(rA) = xor_vec(GPR(rS), uimm @ 0x0000);
  COMPLETED
}

/* --- andi./andis.: no Rc bit, CR0 is ALWAYS updated --------------------- */

union clause ast = ANDI_DOT : (ridx, ridx, bits(16))

mapping clause encdec =
  ANDI_DOT(rS, rA, uimm) <-> 0b011100 @ rS : ridx @ rA : ridx @ uimm : bits(16)

function clause execute(ANDI_DOT(rS, rA, uimm)) = {
  let res = GPR(rS) & extz(uimm);
  GPR(rA) = res;
  set_cr0(res);
  COMPLETED
}

union clause ast = ANDIS_DOT : (ridx, ridx, bits(16))

mapping clause encdec =
  ANDIS_DOT(rS, rA, uimm) <-> 0b011101 @ rS : ridx @ rA : ridx @ uimm : bits(16)

function clause execute(ANDIS_DOT(rS, rA, uimm)) = {
  let res = GPR(rS) & (uimm @ 0x0000);
  GPR(rA) = res;
  set_cr0(res);
  COMPLETED
}

/* --- X-form logicals ---------------------------------------------------- */

/* Layout for all of them: 31 | S | A | B | XO(10) | Rc — note the encoding
 * names the SOURCE register first and the DESTINATION (rA) second, the
 * opposite of the arithmetic instructions. */
val logical_result : (ridx, word, bits(1)) -> Completion
function logical_result(rA, res, rc) = {
  GPR(rA) = res;
  if rc == 0b1 then set_cr0(res);
  COMPLETED
}

union clause ast = AND : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  AND(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0000011100 @ rc : bits(1)

function clause execute(AND(rS, rA, rB, rc)) =
  logical_result(rA, GPR(rS) & GPR(rB), rc)

union clause ast = OR : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  OR(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0110111100 @ rc : bits(1)

function clause execute(OR(rS, rA, rB, rc)) =
  logical_result(rA, GPR(rS) | GPR(rB), rc)

union clause ast = XOR : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  XOR(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0100111100 @ rc : bits(1)

function clause execute(XOR(rS, rA, rB, rc)) =
  logical_result(rA, xor_vec(GPR(rS), GPR(rB)), rc)

union clause ast = NAND : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  NAND(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0111011100 @ rc : bits(1)

function clause execute(NAND(rS, rA, rB, rc)) =
  logical_result(rA, not_vec(GPR(rS) & GPR(rB)), rc)

union clause ast = NOR : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  NOR(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0001111100 @ rc : bits(1)

function clause execute(NOR(rS, rA, rB, rc)) =
  logical_result(rA, not_vec(GPR(rS) | GPR(rB)), rc)

union clause ast = EQV : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  EQV(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0100011100 @ rc : bits(1)

function clause execute(EQV(rS, rA, rB, rc)) =
  logical_result(rA, not_vec(xor_vec(GPR(rS), GPR(rB))), rc)

union clause ast = ANDC : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  ANDC(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0000111100 @ rc : bits(1)

function clause execute(ANDC(rS, rA, rB, rc)) =
  logical_result(rA, GPR(rS) & not_vec(GPR(rB)), rc)

union clause ast = ORC : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  ORC(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0110011100 @ rc : bits(1)

function clause execute(ORC(rS, rA, rB, rc)) =
  logical_result(rA, GPR(rS) | not_vec(GPR(rB)), rc)

/* --- Sign extension and leading-zero count ------------------------------ */

/* extsb[.] rA,rS (XO=954): rA = EXTS(rS[24:31]) in manual numbering, i.e.
 * sign-extend the low byte. */
union clause ast = EXTSB : (ridx, ridx, bits(1))

mapping clause encdec =
  EXTSB(rS, rA, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ 0b00000 @ 0b1110111010 @ rc : bits(1)

function clause execute(EXTSB(rS, rA, rc)) =
  logical_result(rA, exts(GPR(rS)[7 .. 0]), rc)

/* extsh[.] rA,rS (XO=922): sign-extend the low halfword. */
union clause ast = EXTSH : (ridx, ridx, bits(1))

mapping clause encdec =
  EXTSH(rS, rA, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ 0b00000 @ 0b1110011010 @ rc : bits(1)

function clause execute(EXTSH(rS, rA, rc)) =
  logical_result(rA, exts(GPR(rS)[15 .. 0]), rc)

/* cntlzw[.] rA,rS (XO=26): number of leading zeros, 0..32.  The result is
 * never negative, so CR0[LT] is always cleared when Rc=1, as the ch. 10
 * page requires — no special case needed. */
union clause ast = CNTLZW : (ridx, ridx, bits(1))

mapping clause encdec =
  CNTLZW(rS, rA, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ 0b00000 @ 0b0000011010 @ rc : bits(1)

function clause execute(CNTLZW(rS, rA, rc)) =
  logical_result(rA, to_word(count_leading_zeros(GPR(rS))), rc)

/* --- Rotate ------------------------------------------------------------- */

/* ROTL(x, n): rotate a 32-bit value left by n, bits leaving position 0
 * (manual numbering) re-entering at position 31 (§3.3.4).  Doubling the
 * value and slicing is exact for every n in 0..31, n = 0 included. */
val ROTL : forall 'n, 0 <= 'n <= 31. (word, int('n)) -> word
function ROTL(x, n) = slice(x @ x, 32 - n, 32)

/* MASK(MB, ME) (§3.3.4): ones from manual bit MB through manual bit ME
 * inclusive; when MB > ME the run of ones wraps from bit 31 round to bit 0,
 * which is why an all-zero mask cannot be specified (MB = ME + 1 selects
 * every bit).  Indices here are manual bit numbers, so the loop writes
 * sail bit 31 - i. */
val MASK : (bits(5), bits(5)) -> word
function MASK(mb, me) = {
  let b = unsigned(mb);
  let e = unsigned(me);
  var m : word = zeros(32);
  foreach (i from 0 to 31) {
    let inside = if b <= e then (b <= i) & (i <= e)
                 else (i >= b) | (i <= e);
    if inside then m[31 - i] = bitone
  };
  m
}

/* rlwinm[.] rA,rS,SH,MB,ME (opcode 21): rA = ROTL(rS, SH) & MASK(MB, ME). */
union clause ast = RLWINM : (ridx, ridx, bits(5), bits(5), bits(5), bits(1))

mapping clause encdec =
  RLWINM(rS, rA, sh, mb, me, rc) <->
    0b010101 @ rS : ridx @ rA : ridx @ sh : bits(5) @ mb : bits(5)
    @ me : bits(5) @ rc : bits(1)

function clause execute(RLWINM(rS, rA, sh, mb, me, rc)) =
  logical_result(rA, ROTL(GPR(rS), unsigned(sh)) & MASK(mb, me), rc)

/* rlwnm[.] rA,rS,rB,MB,ME (opcode 23): as rlwinm, rotate amount from
 * rB[27:31] (manual) — the rest of rB is ignored. */
union clause ast = RLWNM : (ridx, ridx, ridx, bits(5), bits(5), bits(1))

mapping clause encdec =
  RLWNM(rS, rA, rB, mb, me, rc) <->
    0b010111 @ rS : ridx @ rA : ridx @ rB : ridx @ mb : bits(5)
    @ me : bits(5) @ rc : bits(1)

function clause execute(RLWNM(rS, rA, rB, mb, me, rc)) =
  logical_result(rA, ROTL(GPR(rS), unsigned(GPR(rB)[4 .. 0])) & MASK(mb, me), rc)

/* rlwimi[.] rA,rS,SH,MB,ME (opcode 20): insert the rotated data into rA
 * under the mask, leaving the unmasked bits of rA alone. */
union clause ast = RLWIMI : (ridx, ridx, bits(5), bits(5), bits(5), bits(1))

mapping clause encdec =
  RLWIMI(rS, rA, sh, mb, me, rc) <->
    0b010100 @ rS : ridx @ rA : ridx @ sh : bits(5) @ mb : bits(5)
    @ me : bits(5) @ rc : bits(1)

function clause execute(RLWIMI(rS, rA, sh, mb, me, rc)) = {
  let m = MASK(mb, me);
  let r = ROTL(GPR(rS), unsigned(sh));
  logical_result(rA, (r & m) | (GPR(rA) & not_vec(m)), rc)
}

/* --- Shift -------------------------------------------------------------- */

/* The register-form shifts take a 6-bit amount from rB[26:31] (manual): the
 * count proper is rB[27:31] = sail rB[4:0], and rB[26] = sail rB[5] means
 * "32 or more", which zeroes the result (or fills it with the sign, for
 * sraw).  Everything above those six bits of rB is ignored.
 *
 * NOTE the ch. 10 slw page says "bit 16 of rB" where every other statement
 * of the rule — Table 3-9, and the srw and sraw pages — says bit 26; bit 26
 * is what is implemented here.
 *
 * Rotate and shift instructions never touch XER[OV] or XER[SO], and only
 * the algebraic right shifts touch XER[CA] (§3.3.4). */

union clause ast = SLW : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  SLW(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0000011000 @ rc : bits(1)

function clause execute(SLW(rS, rA, rB, rc)) = {
  let b = GPR(rB);
  let res = if b[5] == bitone then zeros(32)
            else sail_shiftleft(GPR(rS), unsigned(b[4 .. 0]));
  logical_result(rA, res, rc)
}

union clause ast = SRW : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  SRW(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1000011000 @ rc : bits(1)

function clause execute(SRW(rS, rA, rB, rc)) = {
  let b = GPR(rB);
  let res = if b[5] == bitone then zeros(32)
            else sail_shiftright(GPR(rS), unsigned(b[4 .. 0]));
  logical_result(rA, res, rc)
}

/* Shared algebraic right shift.  XER[CA] is set iff the value is negative
 * AND at least one 1-bit is shifted out of position 31 (ch. 10 srawi page),
 * so a shift of zero always clears it. */
val exec_sra : (ridx, word, range(0, 31), bool, bits(1)) -> Completion
function exec_sra(rA, s, n, fill, rc) = {
  let neg = s[31] == bitone;
  /* bits that fall off the right end: the low n bits of s */
  let lost = s & not_vec(sail_shiftleft(ones(32), n));
  let res = if fill then (if neg then ones(32) else zeros(32))
            else sail_arith_shiftright(s, n);
  harness_note_write(hw_xer, hw_xer_ca);
  XER[CA] = bool_to_bits(neg & (if fill then s != zeros(32) else lost != zeros(32)));
  logical_result(rA, res, rc)
}

union clause ast = SRAW : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  SRAW(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1100011000 @ rc : bits(1)

function clause execute(SRAW(rS, rA, rB, rc)) = {
  let b = GPR(rB);
  exec_sra(rA, GPR(rS), unsigned(b[4 .. 0]), b[5] == bitone, rc)
}

/* srawi[.] rA,rS,SH (XO=824): SH is a 5-bit immediate, so there is no
 * "32 or more" case. */
union clause ast = SRAWI : (ridx, ridx, bits(5), bits(1))

mapping clause encdec =
  SRAWI(rS, rA, sh, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ sh : bits(5) @ 0b1100111000 @ rc : bits(1)

function clause execute(SRAWI(rS, rA, sh, rc)) =
  exec_sra(rA, GPR(rS), unsigned(sh), false, rc)

/* --- Trap --------------------------------------------------------------- */

/* The five TO bits each name a comparison; the instruction traps if any
 * selected comparison holds (ch. 10, tw page).  TO arrives msb-first in
 * manual order, so manual TO[0] is sail to[4]:
 *   TO[0] signed <   TO[1] signed >   TO[2] equal
 *   TO[3] unsigned < TO[4] unsigned >
 * TO = 0 therefore never traps, and TO = 31 always does. */
/* NOTE the field is spelled `tofld` throughout: `to` is a Sail keyword. */
val trap_cond : (bits(5), word, word) -> bool
function trap_cond(tofld, a, b) = {
  let sa = signed(a);
  let sb = signed(b);
  let ua = unsigned(a);
  let ub = unsigned(b);
  ((tofld[4] == bitone) & (sa < sb))
  | ((tofld[3] == bitone) & (sa > sb))
  | ((tofld[2] == bitone) & (a == b))
  | ((tofld[1] == bitone) & (ua < ub))
  | ((tofld[0] == bitone) & (ua > ub))
}

/* tw TO,rA,rB (X-form, XO=4) */
union clause ast = TW : (bits(5), ridx, ridx)

mapping clause encdec =
  TW(tofld, rA, rB) <->
    0b011111 @ tofld : bits(5) @ rA : ridx @ rB : ridx @ 0b0000000100 @ 0b0

function clause execute(TW(tofld, rA, rB)) =
  if trap_cond(tofld, GPR(rA), GPR(rB)) then program_exception(Prog_Trap)
  else COMPLETED

/* twi TO,rA,SIMM (opcode 3): compared against the sign-extended immediate,
 * for the unsigned comparisons too. */
union clause ast = TWI : (bits(5), ridx, bits(16))

mapping clause encdec =
  TWI(tofld, rA, simm) <-> 0b000011 @ tofld : bits(5) @ rA : ridx @ simm : bits(16)

function clause execute(TWI(tofld, rA, simm)) =
  if trap_cond(tofld, GPR(rA), exts(simm)) then program_exception(Prog_Trap)
  else COMPLETED

$endif
