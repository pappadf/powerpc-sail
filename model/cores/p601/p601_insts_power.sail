/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p601_insts_power.sail — the 28 POWER-architecture holdover instructions
 * implemented by the 601 but absent from PowerPC (MPC601UM Tables 3-2, 3-7,
 * 3-9; individual pages in ch. 10; Appendix B).
 *
 * These live in the core directory because 603/604 must NOT decode them
 * (there they raise an illegal-instruction program exception, which is what
 * the common ILLEGAL fallback does when this file isn't linked in).
 *
 * ALL 28 ARE IMPLEMENTED:
 *   abs[o][.] doz[o][.] dozi nabs[o][.]        (Table 3-2, arithmetic)
 *   mul[o][.] div[o][.] divs[o][.]             (Table 3-2, MQ multiply/divide)
 *   rlmi[.] rrib[.] maskg[.] maskir[.]         (Table 3-8, rotate and mask)
 *   slq[.] srq[.] sliq[.] sriq[.] slliq[.] srliq[.] sllq[.] srlq[.]
 *   sle[.] sre[.] sleq[.] sreq[.] sraiq[.] sraq[.] srea[.]
 *                                              (Table 3-9, shifts with MQ)
 *   lscbx[.]                                   (Table 3-20, string+compare)
 *   clcs                                       (Table 3-44, cache line size)
 *
 * MQ interactions: mul/div/divs and the *q shift instructions read and/or
 * write MQ (Tables 2-6/2-7).  See p601_regs.sail.
 */

$ifndef _P601_INSTS_POWER
$define _P601_INSTS_POWER

/* --- abs[o][.] rD,rA (XO-form, XO=360): rD = |rA| ----------------------- */

union clause ast = P601_ABS : (ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  P601_ABS(rD, rA, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ 0b00000 @ oe : bits(1) @ 0b101101000 @ rc : bits(1)

function clause execute(P601_ABS(rD, rA, oe, rc)) = {
  let a = GPR(rA);
  /* abs of the most negative number overflows and returns it unchanged */
  let res = if signed(a) < 0 then (zeros(32) - a) else a;
  if oe == 0b1 then {
    let ov = a == 0x80000000;
    XER[OV] = bool_to_bits(ov);
    if ov then XER[SO] = 0b1
  };
  GPR(rD) = res;
  if rc == 0b1 then set_cr0(res);
  COMPLETED
}

/* --- nabs[o][.] rD,rA (XO-form, XO=488): rD = -|rA| --------------------- */

/* "Note that nabs never overflows.  If OE=1 then XER(OV) is cleared to zero
 * and XER(SO) is not changed" (ch. 10 page) — which is exactly what
 * arith_result does with ov = 0, so no special case is needed.  The most
 * negative number is its own negative absolute value and needs none either. */
union clause ast = P601_NABS : (ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  P601_NABS(rD, rA, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ 0b00000 @ oe : bits(1) @ 0b111101000 @ rc : bits(1)

function clause execute(P601_NABS(rD, rA, oe, rc)) = {
  let a = GPR(rA);
  let res = if signed(a) < 0 then a else (zeros(32) - a);
  arith_result(rD, res, 0b0, oe, rc);
  COMPLETED
}

/* --- doz[o][.] / dozi rD,rA,rB|SIMM: difference or zero ----------------- */

/* "The sum ¬(rA)+(rB)+1 is placed into rD.  If the value in rA is
 * algebraically greater than the value in rB, rD is set to zero" — a
 * subtract that saturates at zero, which C's `max(b - a, 0)` compiles to.
 *
 * "If OE=1, OV can only be set on positive overflows" (ch. 10 dozx page):
 * the difference is only kept when rA <= rB, where the true result is
 * non-negative, so any overflow there is a positive one; the branch that
 * forces zero cannot overflow because it does not compute a difference. */
val exec_doz : (ridx, word, word, bits(1), bits(1)) -> Completion
function exec_doz(rD, a, b, oe, rc) = {
  let (diff, _, ov) = add_with_carry(not_vec(a), b, 0b1);
  let saturate = signed(a) > signed(b);
  arith_result(rD, if saturate then zeros(32) else diff,
               if saturate then 0b0 else ov, oe, rc);
  COMPLETED
}

union clause ast = P601_DOZ : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  P601_DOZ(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b100001000 @ rc : bits(1)

function clause execute(P601_DOZ(rD, rA, rB, oe, rc)) =
  exec_doz(rD, GPR(rA), GPR(rB), oe, rc)

/* dozi has neither OE nor Rc — "Other registers altered: None". */
union clause ast = P601_DOZI : (ridx, ridx, bits(16))

mapping clause encdec =
  P601_DOZI(rD, rA, simm) <-> 0b001001 @ rD : ridx @ rA : ridx @ simm : bits(16)

function clause execute(P601_DOZI(rD, rA, simm)) =
  exec_doz(rD, GPR(rA), exts(simm), 0b0, 0b0)

/* --- mul[o][.] rD,rA,rB (XO-form, XO=107): the full 64-bit product ------ */

/* The POWER multiply keeps both halves: manual bits 0-31 of the product (the
 * HIGH-order word) go to rD and bits 32-63 (the low word) to MQ.  Two
 * consequences that catch the eye:
 *   - with Rc=1 "LT, GT and EQ reflect the result in the MQ register", i.e.
 *     CR0 describes the LOW word while rD holds the high one;
 *   - OV is the same condition as mullw's — the product does not fit in 32
 *     bits — even though rD here holds the part that does not fit.
 * The operands are signed: mul is the POWER ancestor of mulhw, and its
 * overflow test only makes sense for a signed product. */
union clause ast = P601_MUL : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  P601_MUL(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b001101011 @ rc : bits(1)

function clause execute(P601_MUL(rD, rA, rB, oe, rc)) = {
  let prod = signed(GPR(rA)) * signed(GPR(rB));
  let ov = bool_to_bits((prod < -2147483648) | (prod > 2147483647));
  if oe == 0b1 then {
    XER[OV] = ov;
    if ov == 0b1 then XER[SO] = 0b1
  };
  MQ = get_slice_int(32, prod, 0);
  GPR(rD) = get_slice_int(32, prod, 32);
  if rc == 0b1 then set_cr0(MQ);
  COMPLETED
}

/* --- div[o][.] / divs[o][.] rD,rA,rB (XO=331 / 363) --------------------- */

/* Both place the quotient in rD and the REMAINDER in MQ, and both describe
 * the result by an equation rather than a rounding rule:
 *   dividend = (divisor * quotient) + remainder
 * with "the remainder has the same sign as the dividend" — that is division
 * truncating toward zero, tdiv_int/tmod_int.  They differ only in the
 * dividend: div takes the 64-bit (rA)||(MQ), divs the 32-bit (rA).
 *
 * With Rc=1 "the CR bits LT, GT and EQ reflect the remainder", not the
 * quotient — so CR0 is computed from MQ.
 *
 * Overflow is "the quotient cannot be represented in 32 bits", which covers
 * a zero divisor as well as a quotient out of range.  One overflow has
 * defined results: for -2^31 / -1 "the MQ register is cleared to zero and
 * -2^31 is placed in rD".  UNDEF (ch. 10 div/divs pages): for every other
 * overflow rD, MQ and CR0 are undefined, so under the model's policy rD and
 * MQ keep their previous values and CR0 (Rc=1) then records the old MQ. */
val exec_pwr_divide : (ridx, int, word, bits(1), bits(1)) -> Completion
function exec_pwr_divide(rD, dividend, b, oe, rc) = {
  let divisor = signed(b);
  var ov : bool = true;
  if divisor != 0 then {
    let q = tdiv_int(dividend, divisor);
    if (q >= -2147483648) & (q <= 2147483647) then {
      ov = false;
      GPR(rD) = get_slice_int(32, q, 0);
      MQ = get_slice_int(32, tmod_int(dividend, divisor), 0)
    } else if (dividend == -2147483648) & (divisor == -1) then {
      GPR(rD) = 0x80000000;
      MQ = zeros(32)
    }
  };
  if oe == 0b1 then {
    XER[OV] = bool_to_bits(ov);
    if ov then XER[SO] = 0b1
  };
  if rc == 0b1 then set_cr0(MQ);
  COMPLETED
}

union clause ast = P601_DIV : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  P601_DIV(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b101001011 @ rc : bits(1)

function clause execute(P601_DIV(rD, rA, rB, oe, rc)) =
  exec_pwr_divide(rD, signed(GPR(rA) @ MQ), GPR(rB), oe, rc)

union clause ast = P601_DIVS : (ridx, ridx, ridx, bits(1), bits(1))

mapping clause encdec =
  P601_DIVS(rD, rA, rB, oe, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ oe : bits(1) @ 0b101101011 @ rc : bits(1)

function clause execute(P601_DIVS(rD, rA, rB, oe, rc)) =
  exec_pwr_divide(rD, signed(GPR(rA)), GPR(rB), oe, rc)

/* --- Rotate and mask (Table 3-8) ---------------------------------------- */

/* rlmi[.] rA,rS,rB,MB,ME (M-form, opcode 22): rlwimi with the rotate amount
 * taken from a register instead of an immediate — the one combination the
 * PowerPC architecture dropped (it kept rlwnm, which masks rather than
 * inserts, and rlwimi, which inserts by an immediate amount).  The rotate
 * amount is rB[27:31], as for every other register-controlled rotate; the
 * rest of rB is ignored. */
union clause ast = P601_RLMI : (ridx, ridx, ridx, bits(5), bits(5), bits(1))

mapping clause encdec =
  P601_RLMI(rS, rA, rB, mb, me, rc) <->
    0b010110 @ rS : ridx @ rA : ridx @ rB : ridx @ mb : bits(5)
    @ me : bits(5) @ rc : bits(1)

function clause execute(P601_RLMI(rS, rA, rB, mb, me, rc)) = {
  let m = MASK(mb, me);
  let r = ROTL(GPR(rS), unsigned(GPR(rB)[4 .. 0]));
  logical_result(rA, (r & m) | (GPR(rA) & not_vec(m)), rc)
}

/* rrib[.] rA,rS,rB (X-form, XO=537): "bit 0 of rS is rotated right the amount
 * specified by bits 27-31 of rB.  The bit is then inserted into rA" — a
 * single-bit insert, rA[n] <- rS[0] in manual numbering.  Everything else in
 * rA is left alone, so this is the bit-granular sibling of maskir. */
union clause ast = P601_RRIB : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_RRIB(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1000011001 @ rc : bits(1)

function clause execute(P601_RRIB(rS, rA, rB, rc)) = {
  var res = GPR(rA);
  res[31 - unsigned(GPR(rB)[4 .. 0])] = GPR(rS)[31];
  logical_result(rA, res, rc)
}

/* maskg[.] rA,rS,rB (XO=29): generate a mask of ones running from manual bit
 * mstart = rS[27:31] through mstop = rB[27:31].  The three cases the ch. 10
 * page lists — mstart <= mstop, mstart = mstop + 1 (all ones), and
 * mstart > mstop + 1 (the run wraps round bit 31) — are exactly the two
 * branches of the architecture's own MASK(MB, ME) (§3.3.4), the middle case
 * being the wrapping branch with nothing excluded.  So the POWER mask
 * generator and the PowerPC one are the same function with its arguments in
 * registers.  (The page prints the middle condition as "mstart = mstop = 1",
 * which is OCR damage: the wrapping branch below gives all ones for
 * mstart = mstop + 1 whatever mstop is.) */
union clause ast = P601_MASKG : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_MASKG(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0000011101 @ rc : bits(1)

function clause execute(P601_MASKG(rS, rA, rB, rc)) =
  logical_result(rA, MASK(GPR(rS)[4 .. 0], GPR(rB)[4 .. 0]), rc)

/* maskir[.] rA,rS,rB (XO=541): "register rS is inserted into rA under control
 * of the mask in rB" — the merge half of rlwimi with a register mask and no
 * rotate.  maskg is what usually produces rB. */
union clause ast = P601_MASKIR : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_MASKIR(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1000011101 @ rc : bits(1)

function clause execute(P601_MASKIR(rS, rA, rB, rc)) = {
  let m = GPR(rB);
  logical_result(rA, (GPR(rS) & m) | (GPR(rA) & not_vec(m)), rc)
}

/* --- Shifts with MQ (Table 3-9) ----------------------------------------- */

/* Fifteen instructions that are all the same three steps — rotate rS, build a
 * mask, combine — differing only in which mask, what the rotated word is
 * combined with, and whether MQ is written.  Every ch. 10 page in the family
 * is written in those terms, so the helpers below are named after them:
 *
 *   ..._and    rA <- r & m,                MQ <- r   (sle sliq sre sriq slq srq)
 *   ..._merge  rA <- (r & m) | (MQ & ¬m),  MQ <- r   (sleq slliq sreq srliq)
 *   ..._long   rA <- (r & m) | (MQ & ¬m),  MQ kept   (sllq srlq)
 *   ..._alg    rA <- (r & m) | (sign & ¬m), MQ <- r, and XER[CA]
 *                                                    (sraiq sraq srea)
 *
 * MQ is what makes them useful: the pairs (sle, sllq) and (sre, srlq) shift a
 * 64-bit quantity by 0-63 in two instructions, the first leaving the bits that
 * cross the word boundary in MQ for the second to merge in.  That is also what
 * settles the two OCR-damaged sentences on the sllq page — see below.
 *
 * The shift amount n is rB[27:31] (or the SH field), and for the six
 * instructions whose name ends in q (slq srq sllq srlq sraq, and sre's
 * partner) rB[26] additionally means "32 or more", exactly as it does for the
 * PowerPC slw/srw/sraw.  Everything above those six bits of rB is ignored. */

/* "A mask of 32 - n ones followed by n zeros" and its mirror image, the two
 * masks every page in the family names.  Shifting a word of ones gives both
 * for n = 0..31, all ones included. */
val mask_left : range(0, 31) -> word
function mask_left(n) = sail_shiftleft(ones(32), n)

val mask_right : range(0, 31) -> word
function mask_right(n) = sail_shiftright(ones(32), n)

/* "Rotated left 32 - n bits", i.e. rotated right by n.  Written directly
 * rather than as ROTL(x, 32 - n) so that n = 0 needs no special case. */
val ROTR : (word, range(0, 31)) -> word
function ROTR(x, n) = slice(x @ x, n, 32)

val pwr_shift_and : (ridx, word, word, bits(1)) -> Completion
function pwr_shift_and(rA, r, m, rc) = {
  MQ = r;
  logical_result(rA, r & m, rc)
}

val pwr_shift_merge : (ridx, word, word, bits(1)) -> Completion
function pwr_shift_merge(rA, r, m, rc) = {
  let res = (r & m) | (MQ & not_vec(m));
  MQ = r;
  logical_result(rA, res, rc)
}

/* The long forms merge into MQ without disturbing it — they are the second
 * half of a two-instruction 64-bit shift, and MQ still holds what the first
 * half left there. */
val pwr_shift_long : (ridx, word, word, bits(1)) -> Completion
function pwr_shift_long(rA, r, m, rc) =
  logical_result(rA, (r & m) | (MQ & not_vec(m)), rc)

/* The algebraic forms merge with "a word of 32 sign bits from rS" instead of
 * with MQ, and set XER[CA] from "the rotated word ANDed with the complement
 * of the generated mask ... ORed together and then ANDed with bit 0 of rS" —
 * that is, 1 iff the value was negative and a 1-bit was shifted out.  Which is
 * the same rule as the PowerPC sraw/srawi (see exec_sra), stated over the
 * rotated word rather than over the discarded low bits. */
val pwr_shift_alg : (ridx, word, word, word, bits(1)) -> Completion
function pwr_shift_alg(rA, s, r, m, rc) = {
  let neg = s[31] == bitone;
  let sign = if neg then ones(32) else zeros(32);
  XER[CA] = bool_to_bits(neg & ((r & not_vec(m)) != zeros(32)));
  MQ = r;
  logical_result(rA, (r & m) | (sign & not_vec(m)), rc)
}

/* --- Register-amount shifts --------------------------------------------- */

/* sle[.] rA,rS,rB (XO=153): shift left extended — a plain shift left whose
 * rotated word is kept in MQ for a following sllq. */
union clause ast = P601_SLE : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_SLE(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0010011001 @ rc : bits(1)

function clause execute(P601_SLE(rS, rA, rB, rc)) = {
  let n = unsigned(GPR(rB)[4 .. 0]);
  pwr_shift_and(rA, ROTL(GPR(rS), n), mask_left(n), rc)
}

/* sre[.] rA,rS,rB (XO=665): the mirror image, shift right extended. */
union clause ast = P601_SRE : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_SRE(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1010011001 @ rc : bits(1)

function clause execute(P601_SRE(rS, rA, rB, rc)) = {
  let n = unsigned(GPR(rB)[4 .. 0]);
  pwr_shift_and(rA, ROTR(GPR(rS), n), mask_right(n), rc)
}

/* sleq[.] (XO=217) / sreq[.] (XO=729): as sle/sre, but the bits shifted in
 * come from MQ rather than being zero. */
union clause ast = P601_SLEQ : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_SLEQ(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0011011001 @ rc : bits(1)

function clause execute(P601_SLEQ(rS, rA, rB, rc)) = {
  let n = unsigned(GPR(rB)[4 .. 0]);
  pwr_shift_merge(rA, ROTL(GPR(rS), n), mask_left(n), rc)
}

union clause ast = P601_SREQ : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_SREQ(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1011011001 @ rc : bits(1)

function clause execute(P601_SREQ(rS, rA, rB, rc)) = {
  let n = unsigned(GPR(rB)[4 .. 0]);
  pwr_shift_merge(rA, ROTR(GPR(rS), n), mask_right(n), rc)
}

/* slq[.] (XO=152) / srq[.] (XO=664): as sle/sre but honouring rB[26], where
 * "a mask of all zeros is generated" — a shift of 32 or more clears rA, as it
 * does for slw/srw.  MQ still receives the rotated word. */
union clause ast = P601_SLQ : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_SLQ(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0010011000 @ rc : bits(1)

function clause execute(P601_SLQ(rS, rA, rB, rc)) = {
  let b = GPR(rB);
  let n = unsigned(b[4 .. 0]);
  let m = if b[5] == bitzero then mask_left(n) else zeros(32);
  pwr_shift_and(rA, ROTL(GPR(rS), n), m, rc)
}

union clause ast = P601_SRQ : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_SRQ(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1010011000 @ rc : bits(1)

function clause execute(P601_SRQ(rS, rA, rB, rc)) = {
  let b = GPR(rB);
  let n = unsigned(b[4 .. 0]);
  let m = if b[5] == bitzero then mask_right(n) else zeros(32);
  pwr_shift_and(rA, ROTR(GPR(rS), n), m, rc)
}

/* --- Immediate and long shifts ------------------------------------------ */

/* sliq[.] (XO=184) / sriq[.] (XO=696): sle/sre with the amount in the SH
 * field, so there is no "32 or more" case. */
union clause ast = P601_SLIQ : (ridx, ridx, bits(5), bits(1))

mapping clause encdec =
  P601_SLIQ(rS, rA, sh, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ sh : bits(5) @ 0b0010111000 @ rc : bits(1)

function clause execute(P601_SLIQ(rS, rA, sh, rc)) =
  pwr_shift_and(rA, ROTL(GPR(rS), unsigned(sh)), mask_left(unsigned(sh)), rc)

union clause ast = P601_SRIQ : (ridx, ridx, bits(5), bits(1))

mapping clause encdec =
  P601_SRIQ(rS, rA, sh, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ sh : bits(5) @ 0b1010111000 @ rc : bits(1)

function clause execute(P601_SRIQ(rS, rA, sh, rc)) =
  pwr_shift_and(rA, ROTR(GPR(rS), unsigned(sh)), mask_right(unsigned(sh)), rc)

/* slliq[.] (XO=248) / srliq[.] (XO=760): sleq/sreq with an immediate amount. */
union clause ast = P601_SLLIQ : (ridx, ridx, bits(5), bits(1))

mapping clause encdec =
  P601_SLLIQ(rS, rA, sh, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ sh : bits(5) @ 0b0011111000 @ rc : bits(1)

function clause execute(P601_SLLIQ(rS, rA, sh, rc)) =
  pwr_shift_merge(rA, ROTL(GPR(rS), unsigned(sh)), mask_left(unsigned(sh)), rc)

union clause ast = P601_SRLIQ : (ridx, ridx, bits(5), bits(1))

mapping clause encdec =
  P601_SRLIQ(rS, rA, sh, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ sh : bits(5) @ 0b1011111000 @ rc : bits(1)

function clause execute(P601_SRLIQ(rS, rA, sh, rc)) =
  pwr_shift_merge(rA, ROTR(GPR(rS), unsigned(sh)), mask_right(unsigned(sh)), rc)

/* sllq[.] (XO=216) / srlq[.] (XO=728): the second half of a 64-bit shift.
 * They leave MQ alone, and for a count of 32 or more (rB[26]=1) they merge a
 * word of ZEROS with MQ under the complementary mask, which delivers MQ's
 * surviving half — for srlq, MQ with its high n bits cleared.
 *
 * MANUAL GLITCH (ch. 10 sllq page): its two rB[26] cases read "a mask of
 * 32 - n ones followed by n zeros ... a word of zeros is then merged with the
 * contents of the MQ register" and "a mask of 32 - n ones followed by n ones",
 * which are respectively the wrong sentence (it drops the rotated word
 * entirely, so nothing of rS would reach rA) and an impossible mask (32 - n
 * ones followed by n ones is every bit).  The srlq page states the same pair
 * of cases correctly, and the two must mirror each other: the rB[26]=0 case
 * merges the ROTATED WORD with MQ, and the rB[26]=1 mask is "32 - n ZEROS
 * followed by n ones".  That reading is also the only one that makes the
 * sle/sllq pair shift a doubleword left by 32..63 correctly (the result is
 * then MQ with its low n bits cleared, which is the low word shifted up by
 * n = count - 32); the literal all-ones reading would give zero. */
union clause ast = P601_SLLQ : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_SLLQ(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0011011000 @ rc : bits(1)

function clause execute(P601_SLLQ(rS, rA, rB, rc)) = {
  let b = GPR(rB);
  let n = unsigned(b[4 .. 0]);
  if b[5] == bitzero then
    pwr_shift_long(rA, ROTL(GPR(rS), n), mask_left(n), rc)
  else
    pwr_shift_long(rA, zeros(32), not_vec(mask_left(n)), rc)
}

union clause ast = P601_SRLQ : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_SRLQ(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1011011000 @ rc : bits(1)

function clause execute(P601_SRLQ(rS, rA, rB, rc)) = {
  let b = GPR(rB);
  let n = unsigned(b[4 .. 0]);
  if b[5] == bitzero then
    pwr_shift_long(rA, ROTR(GPR(rS), n), mask_right(n), rc)
  else
    pwr_shift_long(rA, zeros(32), not_vec(mask_right(n)), rc)
}

/* --- Algebraic shifts --------------------------------------------------- */

/* sraiq[.] (XO=952), sraq[.] (XO=920), srea[.] (XO=921): shift right
 * algebraic, keeping the rotated word in MQ and setting XER[CA] as srawi
 * does.  sraq honours rB[26] ("a mask of all zeros" — the result is then all
 * sign bits, as for sraw); srea does not, and takes its whole amount from
 * rB[27:31]. */
union clause ast = P601_SRAIQ : (ridx, ridx, bits(5), bits(1))

mapping clause encdec =
  P601_SRAIQ(rS, rA, sh, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ sh : bits(5) @ 0b1110111000 @ rc : bits(1)

function clause execute(P601_SRAIQ(rS, rA, sh, rc)) = {
  let s = GPR(rS);
  pwr_shift_alg(rA, s, ROTR(s, unsigned(sh)), mask_right(unsigned(sh)), rc)
}

union clause ast = P601_SRAQ : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_SRAQ(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1110011000 @ rc : bits(1)

function clause execute(P601_SRAQ(rS, rA, rB, rc)) = {
  let s = GPR(rS);
  let b = GPR(rB);
  let n = unsigned(b[4 .. 0]);
  let m = if b[5] == bitzero then mask_right(n) else zeros(32);
  pwr_shift_alg(rA, s, ROTR(s, n), m, rc)
}

union clause ast = P601_SREA : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_SREA(rS, rA, rB, rc) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1110011001 @ rc : bits(1)

function clause execute(P601_SREA(rS, rA, rB, rc)) = {
  let s = GPR(rS);
  let n = unsigned(GPR(rB)[4 .. 0]);
  pwr_shift_alg(rA, s, ROTR(s, n), mask_right(n), rc)
}

/* --- lscbx[.] rD,rA,rB (X-form, XO=277) --------------------------------- */

/* Load string and compare byte: lswx that stops early on a byte equal to
 * XER[CMPB] (§3.5.6, ch. 10 page).  The matched byte is loaded too, the
 * number of bytes loaded up to and including it replaces XER[BC], and with
 * Rc=1 CR0 reports whether a match was found:
 *      CR0 <- 0b00 || match || XER[SO]
 * Everything else — bytes fill each register left to right, the register
 * sequence wraps through r0, a base register inside the range is skipped —
 * is the ordinary string behaviour shared with lswx.
 *
 * Three deviations from every other load are what make it worth its own
 * clause rather than a flag on exec_load_string:
 *
 *  - it is exempt from the DABR: "no DAE occurs, even if the EA matches"
 *    (Table 2-26), so the transfer uses mem_read_nodabr;
 *  - in an I/O controller interface segment that is not memory-forced it
 *    takes a data access exception with DSISR[5], like lwarx and stwcx.
 *    (§6.10.5, Table 6-3);
 *  - its alignment rule is stricter than the other string instructions':
 *    "an alignment exception [if] any portion of the entire string crosses
 *    into the next 4-Kbyte page ... regardless of the starting address, even
 *    if the operand starts on a word boundary" (§5.4.6.1.4).
 *
 * UNDEF (§3.5.6): the bytes of a partly filled last register, and every
 * register after the one holding the matched byte, are undefined — here the
 * former are zero (as for lswx) and the latter are left alone.  With a byte
 * count of zero the instruction "does not alter register rD or cause a memory
 * access", so it cannot fault whatever the EA (§5.4.3), and CR0 is undefined
 * with Rc=1 — the policy leaves it unchanged. */
union clause ast = P601_LSCBX : (ridx, ridx, ridx, bits(1))

mapping clause encdec =
  P601_LSCBX(rD, rA, rB, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0100010101 @ rc : bits(1)

function clause execute(P601_LSCBX(rD, rA, rB, rc)) = {
  let ea = ea_x(rA, rB);
  let n = unsigned(XER[BC]);
  let inhibit = string_load_inhibit(rA, reg_mask_bit(rB));
  if n == 0 then COMPLETED
  else if nonforced_io_segment(ea) then
    data_access_fault(Fault_IOSegUnsupported, ea, false)
  else if not_bool(string_align_ok(ea, n, Align_string_4k)) then EXCEPTION_TAKEN
  else {
    var ok : bool = true;
    var matched : bool = false;
    var loaded : int = 0;
    foreach (m from 0 to 31) {
      let r = unsigned(add_bits_int(rD, m));   /* wraps mod 32 in 5 bits */
      var acc : word = zeros(32);
      var used : bool = false;
      foreach (j from 0 to 3) {
        let k = 4 * m + j;
        if ok & not_bool(matched) & (k < n) then {
          match mem_read_nodabr(ea + to_word(k), 1) {
            Some(b) => {
              acc = acc | sail_shiftleft(extz(b), 24 - 8 * j);
              used = true;
              loaded = loaded + 1;
              if b == XER[CMPB] then matched = true
            },
            None() => { ok = false }
          }
        }
      };
      if used & (inhibit[r] == bitzero) then { GPRs[r] = acc }
    };
    if ok then {
      if matched then XER[BC] = get_slice_int(7, loaded, 0);
      if rc == 0b1 then CRfield(0, 0b00 @ bool_to_bits(matched) @ XER[SO]);
      COMPLETED
    } else EXCEPTION_TAKEN
  }
}

/* --- clcs rD,rA (X-form, XO=531) ---------------------------------------- */

/* Cache line compute size: POWER's way of asking the implementation how big a
 * cache line is, so that a program could size its cache-management loops
 * without knowing the model (§4.8.1).  On the 601 all four defined queries —
 * instruction line, data line, minimum, maximum — answer 64, the cache being
 * unified with a 64-byte line (two 32-byte sectors).  Note that is the LINE
 * size, not the 32-byte sector dcbz operates on.
 *
 * UNDEF (ch. 10 page): every other rA encoding "returns undefined values",
 * and with Rc=1 CR0 is undefined for every encoding — so under the model's
 * policy rD and CR0 are both left unchanged there, and Rc is decoded and
 * ignored.  Note that rA is an immediate selector here, not a register
 * number: it is the FIELD that is compared, and no GPR is read. */
union clause ast = P601_CLCS : (ridx, ridx, bits(1))

mapping clause encdec =
  P601_CLCS(rD, rA, rc) <->
    0b011111 @ rD : ridx @ rA : ridx @ 0b00000 @ 0b1000010011 @ rc : bits(1)

function clause execute(P601_CLCS(rD, rA, _rc)) = {
  if rA[4 .. 2] == 0b011 then GPR(rD) = to_word(64);
  COMPLETED
}

$endif
