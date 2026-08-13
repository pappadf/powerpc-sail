/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_softfloat.sail — IEEE 754 binary arithmetic for the floating-point
 * unit (MPC601UM §2.5).  Pure functions over bit patterns: nothing here
 * reads or writes architected state, and nothing here knows about the FPSCR
 * enable bits.  ppc_insts_fp.sail turns the results below into register
 * writes, FPSCR updates and exceptions.
 *
 * WHY THIS EXISTS RATHER THAN A SOFTFLOAT LIBRARY.  Sail ships two float
 * facilities and neither serves: `lib/float.sail` declares its operations as
 * external primitives that the C backend has no implementation (or even a C
 * type) for, and the pure-Sail `lib/float/` has add, compare and classify but
 * no multiply, divide or fused multiply-add.  Binding Berkeley SoftFloat
 * through C glue the way sail-riscv does would add a build dependency, and
 * would tie the model to the C backend — the prover backends could not run
 * floating point at all.  There is also a PowerPC-specific reason: with an
 * enabled overflow or underflow the architecture delivers the result with
 * its exponent adjusted by a constant (§5.4.7.4.1, §5.4.7.5.1), which is not
 * something an IEEE library exposes, whereas here it is one addition on the
 * exponent before packing.
 *
 * HOW IT WORKS.  A finite value is carried as an exact triple
 *
 *     (sign, significand, exponent)   meaning   (-1)^sign * sig * 2^exp
 *
 * with `sig` an ORDINARY SAIL INTEGER, which is arbitrary-precision.  Every
 * operation except division is therefore computed EXACTLY — the sum of two
 * doubles whose exponents differ by 2000 is just a 2000-bit integer, and the
 * 106-bit product of a multiply-add is exact by construction, so the
 * "infinitely precise intermediate result" of §2.5.1 is literal here rather
 * than emulated with guard/round/sticky bits.  Division cannot be exact, so
 * it alone computes a few more bits than the format needs and reports the
 * rest through a sticky flag.  Rounding then happens once, in fp_round.
 *
 * The formats differ only in precision and exponent range: PowerPC holds
 * every value in double format and a single-precision instruction merely
 * rounds to 24 bits within the single exponent range before storing the
 * result as a double, which is always exact (§2.5.5).  So one kernel serves
 * both, parameterized by a `single` flag.
 */

$ifndef _PPC_SOFTFLOAT
$define _PPC_SOFTFLOAT

/* --- Format parameters (§2.5.2) ----------------------------------------- */

/* Precision in bits, including the leading significand bit. */
val fp_precision : bool -> int
function fp_precision(single) = if single then 24 else 53

/* Exponent of the smallest normalized number, and of the largest finite. */
val fp_emin : bool -> int
function fp_emin(single) = if single then -126 else -1022

val fp_emax : bool -> int
function fp_emax(single) = if single then 127 else 1023

/* --- Decomposition ------------------------------------------------------ */

enum FpKind = {
  FK_Zero,
  FK_Finite,      /* normalized or denormalized */
  FK_Inf,
  FK_QNaN,
  FK_SNaN
}

val fp_kind : bits(64) -> FpKind
function fp_kind(v) = {
  let biased = v[62 .. 52];
  let frac = v[51 .. 0];
  if biased == zeros(11) then (if frac == zeros(52) then FK_Zero else FK_Finite)
  else if biased == ones(11) then {
    if frac == zeros(52) then FK_Inf
    else if frac[51] == bitone then FK_QNaN else FK_SNaN
  } else FK_Finite
}

val fp_is_nan : bits(64) -> bool
function fp_is_nan(v) = match fp_kind(v) { FK_QNaN => true, FK_SNaN => true, _ => false }

/* Sail enums carry no equality, so the classes that get tested individually
 * rather than matched on get a predicate apiece. */
val fp_is_zero : bits(64) -> bool
function fp_is_zero(v) = match fp_kind(v) { FK_Zero => true, _ => false }

val fp_is_inf : bits(64) -> bool
function fp_is_inf(v) = match fp_kind(v) { FK_Inf => true, _ => false }

val fp_sign : bits(64) -> bits(1)
function fp_sign(v) = [v[63]]

/* The exact value of a finite operand as (significand, exponent), with the
 * significand a non-negative integer: normalized numbers carry the implicit
 * leading bit, denormalized ones do not (§2.5.2.3, §2.5.2.5).  A zero comes
 * back as significand 0. */
val fp_unpack : bits(64) -> (int, int)
function fp_unpack(v) = {
  let biased = unsigned(v[62 .. 52]);
  let frac = unsigned(v[51 .. 0]);
  if biased == 0 then (frac, -1074)                  /* zero or denormal */
  else (frac + 4503599627370496, biased - 1075)      /* 2^52 + fraction  */
}

/* The QNaN an operation generates when it delivers a disabled invalid
 * operation: sign 0, maximum exponent, high-order fraction bit set and
 * nothing else (§2.5.2.7, Figure 2-49). */
let fp_default_qnan : bits(64) = 0x7FF8000000000000

/* Quieten a NaN operand that is being propagated: set the high-order
 * fraction bit, keeping everything else — which is how "specific encodings
 * in QNaNs can be preserved through a sequence of operations" (§2.5.2.7). */
val fp_quieten : bits(64) -> bits(64)
function fp_quieten(v) = v | 0x0008000000000000

/* --- Bit length of an arbitrary-precision integer ----------------------- */

/* Number of bits in the binary representation of x >= 0 (0 for x = 0), which
 * is what locates the leading significand bit of an exact result.  The
 * operands are ordinary Sail integers and can be thousands of bits wide when
 * an addition aligns two far-apart exponents, so the loop takes 64 bits at a
 * stride before finishing bit by bit. */
val fp_int_bits : int -> int
function fp_int_bits(x) = {
  var v : int = x;
  var n : int = 0;
  while v >= 18446744073709551616 do {      /* 2^64 */
    v = tdiv_int(v, 18446744073709551616);
    n = n + 64
  };
  while v > 0 do {
    v = tdiv_int(v, 2);
    n = n + 1
  };
  n
}

/* 2^n for any n, saturating at 1 for n <= 0 so that callers can shift by a
 * computed amount without proving its sign to the typechecker. */
val fp_pow2 : int -> int
function fp_pow2(n) = if n <= 0 then 1 else pow2(n)

/* --- Rounding (§2.5.6, §5.4.7.4, §5.4.7.5) ------------------------------ */

/* The outcome of rounding an exact value to a format.  `sig`/`exp` are the
 * rounded value in the same exact form as the input, so the caller can pack
 * it, or adjust its exponent first for an enabled overflow or underflow. */
struct FpRounded = {
  sign        : bits(1),
  sig         : int,      /* rounded significand; 0 only for an exact zero  */
  exp         : int,      /* value = sig * 2^exp                            */
  inexact     : bool,     /* FPSCR[FI]: the rounding lost something         */
  incremented : bool,     /* FPSCR[FR]: rounding increased the significand  */
  overflow    : bool,     /* magnitude above the format's largest finite    */
  tiny        : bool      /* BEFORE rounding, magnitude below the smallest
                             normalized number (§5.4.7.5)                   */
}

/* Round (-1)^sign * (sig * 2^exp + something smaller if `sticky`) to the
 * given format under FPSCR[RN] = `rn`.
 *
 * `unbounded` selects the exponent range: normally the significand is
 * clamped so that a tiny result comes out denormalized, but an ENABLED
 * underflow wants the result rounded as though the exponent range were
 * unlimited, before being scaled back (§5.4.7.5.1), and that is what this
 * flag asks for. */
val fp_round : (bits(1), int, int, bool, bool, bits(2), bool) -> FpRounded
function fp_round(sign, sig_in, exp_in, sticky_in, single, rn, unbounded) = {
  let p = fp_precision(single);
  let nbits = fp_int_bits(sig_in);
  if sig_in == 0 then
    struct { sign = sign, sig = 0, exp = 0, inexact = sticky_in,
             incremented = false, overflow = false, tiny = false }
  else {
    let etop = exp_in + nbits - 1;              /* exponent of the leading bit */
    let tiny = etop < fp_emin(single);
    /* Exponent of the least significant bit the result may keep: p bits below
     * the leading one, but never below the format's smallest denormal step. */
    let lsb = if unbounded then etop - p + 1
              else max_int(etop - p + 1, fp_emin(single) - p + 1);
    let shift = lsb - exp_in;
    let d = fp_pow2(shift);
    let q = if shift > 0 then tdiv_int(sig_in, d) else sig_in * fp_pow2(0 - shift);
    let rem = if shift > 0 then sig_in - q * d else 0;
    let half = tdiv_int(d, 2);
    let inexact = (rem != 0) | sticky_in;
    /* Which way to round: rem against the midpoint, with `sticky` breaking a
     * tie upward because the true value is then above it (§2.5.1). */
    let round_up : bool = match rn {
      0b00 => (rem > half) | ((rem == half) & (sticky_in | (tmod_int(q, 2) == 1))),
      0b01 => false,
      0b10 => inexact & (sign == 0b0),
      _    => inexact & (sign == 0b1)
    };
    let q1 = if round_up then q + 1 else q;
    /* An increment can carry out of the significand; renormalizing is exact. */
    let carry = q1 == fp_pow2(p);
    let sig_out = if carry then tdiv_int(q1, 2) else q1;
    let exp_out = if carry then lsb + 1 else lsb;
    let etop_out = exp_out + fp_int_bits(sig_out) - 1;
    struct { sign = sign, sig = sig_out, exp = exp_out,
             inexact = inexact, incremented = round_up,
             overflow = etop_out > fp_emax(single), tiny = tiny }
  }
}

/* --- Packing into the double format ------------------------------------- */

/* Encode (-1)^sign * sig * 2^exp as a double.  Every value fp_round can
 * produce fits: a double-precision result is at worst the smallest denormal,
 * and a single-precision one is always a normal double (§2.5.5). */
val fp_pack : (bits(1), int, int) -> bits(64)
function fp_pack(sign, sig, exp) = {
  if sig == 0 then sign @ zeros(63)
  else {
    let nb = fp_int_bits(sig);
    let etop = exp + nb - 1;
    if etop < -1022 then {
      /* Denormal: the significand is whatever multiple of 2^-1074 it is. */
      let m = if exp >= -1074 then sig * fp_pow2(exp + 1074)
              else tdiv_int(sig, fp_pow2(-1074 - exp));
      sign @ zeros(11) @ get_slice_int(52, m, 0)
    } else {
      /* Normal: line the leading bit up with bit 52 and drop it. */
      let m = if nb <= 53 then sig * fp_pow2(53 - nb) else tdiv_int(sig, fp_pow2(nb - 53));
      sign @ get_slice_int(11, etop + 1023, 0) @ get_slice_int(52, m, 0)
    }
  }
}

/* The largest finite number of a format, and infinity, as doubles — the two
 * results a disabled overflow chooses between (§5.4.7.4.1). */
val fp_infinity : bits(1) -> bits(64)
function fp_infinity(sign) = sign @ 0x7FF0000000000000[62 .. 0]

val fp_max_finite : (bits(1), bool) -> bits(64)
function fp_max_finite(sign, single) =
  if single then sign @ 0x47EFFFFFE0000000[62 .. 0]
  else sign @ 0x7FEFFFFFFFFFFFFF[62 .. 0]

/* --- What one arithmetic operation produced ----------------------------- */

/* The kernel evaluates an operation without knowing the FPSCR enable bits,
 * so it reports the exception CONDITIONS it detected and, separately, the
 * value it would deliver.  ppc_insts_fp.sail applies §5.4.7's rules. */
union FpEval = {
  /* An invalid operation: the FPSCR bits to raise, and the QNaN to deliver
   * if FPSCR[VE] = 0 (chosen by the frA-frB-frC propagation rule). */
  Ev_Invalid : (bits(32), bits(64)),
  /* A zero divide: the sign of the infinity to deliver if FPSCR[ZE] = 0. */
  Ev_ZeroDivide : bits(1),
  /* An exact special result, needing no rounding. */
  Ev_Inf : bits(1),
  Ev_Zero : bits(1),
  /* A number: sign, significand, exponent, and whether nonzero bits were
   * dropped below the significand (division only). */
  Ev_Number : (bits(1), int, int, bool)
}

/* The FPSCR invalid-operation bits this file can raise, in FPSCR bit
 * positions (manual bits 7-11; sail 24-20).  Named here rather than shared
 * with the register file so that the kernel stays free-standing. */
let fpscr_bit_vxsnan : bits(32) = 0x01000000   /* manual bit 7  */
let fpscr_bit_vxisi  : bits(32) = 0x00800000   /* manual bit 8  */
let fpscr_bit_vxidi  : bits(32) = 0x00400000   /* manual bit 9  */
let fpscr_bit_vxzdz  : bits(32) = 0x00200000   /* manual bit 10 */
let fpscr_bit_vximz  : bits(32) = 0x00100000   /* manual bit 11 */

/* NaN propagation (§2.5.2.7): the result is frA's NaN if it has one, else
 * frB's, else frC's, else the generated QNaN.  Callers pass the operands in
 * that order, using a non-NaN placeholder for the ones an instruction does
 * not have. */
val fp_propagate_nan : (bits(64), bits(64), bits(64)) -> bits(64)
function fp_propagate_nan(a, b, c) =
  if fp_is_nan(a) then fp_quieten(a)
  else if fp_is_nan(b) then fp_quieten(b)
  else if fp_is_nan(c) then fp_quieten(c)
  else fp_default_qnan

/* Does any operand signal?  An SNaN operand is an invalid operation for
 * every arithmetic instruction (§5.4.7.2). */
val fp_any_snan : (bits(64), bits(64), bits(64)) -> bool
function fp_any_snan(a, b, c) =
  match (fp_kind(a), fp_kind(b), fp_kind(c)) {
    (FK_SNaN, _, _) => true,
    (_, FK_SNaN, _) => true,
    (_, _, FK_SNaN) => true,
    _ => false
  }

/* The invalid-operation outcome shared by every operation whose operands are
 * NaNs: raise VXSNAN if any of them signals, and propagate. */
val fp_nan_result : (bits(64), bits(64), bits(64)) -> FpEval
function fp_nan_result(a, b, c) =
  Ev_Invalid(if fp_any_snan(a, b, c) then fpscr_bit_vxsnan else zeros(32),
             fp_propagate_nan(a, b, c))

/* --- Addition (§2.5.3, ch. 10 fadd/fsub pages) -------------------------- */

/* a + b, with `b` already sign-flipped by the caller for a subtract.
 * `rn` decides the sign of an exact zero result. */
val fp_add_eval : (bits(64), bits(64), bits(2)) -> FpEval
function fp_add_eval(a, b, rn) = {
  let ka = fp_kind(a);
  let kb = fp_kind(b);
  if fp_is_nan(a) | fp_is_nan(b) then fp_nan_result(a, b, fp_default_qnan)
  else match (ka, kb) {
    /* Magnitude subtraction of infinities is the ∞-∞ invalid operation. */
    (FK_Inf, FK_Inf) =>
      if fp_sign(a) != fp_sign(b) then Ev_Invalid(fpscr_bit_vxisi, fp_default_qnan)
      else Ev_Inf(fp_sign(a)),
    (FK_Inf, _) => Ev_Inf(fp_sign(a)),
    (_, FK_Inf) => Ev_Inf(fp_sign(b)),
    _ => {
      let (siga, expa) = fp_unpack(a);
      let (sigb, expb) = fp_unpack(b);
      let e = min_int(expa, expb);
      let va = siga * fp_pow2(expa - e);
      let vb = sigb * fp_pow2(expb - e);
      let sum = (if fp_sign(a) == 0b1 then 0 - va else va)
                + (if fp_sign(b) == 0b1 then 0 - vb else vb);
      if sum == 0 then {
        /* "When the sum of two operands with opposite sign ... is exactly
         * zero, the sign of the result is positive in all rounding modes
         * except round toward -infinity" — but two zeros of the SAME sign
         * keep it, being an addition of like-signed operands (§2.5.3). */
        if fp_is_zero(a) & fp_is_zero(b) & (fp_sign(a) == fp_sign(b)) then
          Ev_Zero(fp_sign(a))
        else Ev_Zero(if rn == 0b11 then 0b1 else 0b0)
      } else if sum < 0 then Ev_Number(0b1, 0 - sum, e, false)
      else Ev_Number(0b0, sum, e, false)
    }
  }
}

/* --- Multiplication ----------------------------------------------------- */

val fp_mul_eval : (bits(64), bits(64)) -> FpEval
function fp_mul_eval(a, c) = {
  let sign = xor_vec(fp_sign(a), fp_sign(c));
  if fp_is_nan(a) | fp_is_nan(c) then fp_nan_result(a, fp_default_qnan, c)
  else match (fp_kind(a), fp_kind(c)) {
    /* Multiplication of infinity by zero, in either order (§5.4.7.2). */
    (FK_Inf, FK_Zero) => Ev_Invalid(fpscr_bit_vximz, fp_default_qnan),
    (FK_Zero, FK_Inf) => Ev_Invalid(fpscr_bit_vximz, fp_default_qnan),
    (FK_Inf, _) => Ev_Inf(sign),
    (_, FK_Inf) => Ev_Inf(sign),
    (FK_Zero, _) => Ev_Zero(sign),
    (_, FK_Zero) => Ev_Zero(sign),
    _ => {
      let (siga, expa) = fp_unpack(a);
      let (sigc, expc) = fp_unpack(c);
      Ev_Number(sign, siga * sigc, expa + expc, false)
    }
  }
}

/* --- Division ----------------------------------------------------------- */

/* The quotient is the only inexact primitive here: it is computed to a few
 * more bits than the format keeps, and whatever is left over becomes the
 * sticky flag that fp_round rounds on. */
val fp_div_eval : (bits(64), bits(64), bool) -> FpEval
function fp_div_eval(a, b, single) = {
  let sign = xor_vec(fp_sign(a), fp_sign(b));
  if fp_is_nan(a) | fp_is_nan(b) then fp_nan_result(a, b, fp_default_qnan)
  else match (fp_kind(a), fp_kind(b)) {
    (FK_Inf, FK_Inf)   => Ev_Invalid(fpscr_bit_vxidi, fp_default_qnan),
    (FK_Zero, FK_Zero) => Ev_Invalid(fpscr_bit_vxzdz, fp_default_qnan),
    (FK_Inf, _)        => Ev_Inf(sign),
    (_, FK_Inf)        => Ev_Zero(sign),
    (FK_Zero, _)       => Ev_Zero(sign),
    /* Finite nonzero over zero: the "exact infinite result from finite
     * operands" the manual calls a zero divide (§5.4.7.3). */
    (_, FK_Zero)       => Ev_ZeroDivide(sign),
    _ => {
      let (siga, expa) = fp_unpack(a);
      let (sigb, expb) = fp_unpack(b);
      /* Scale so the quotient has two or three bits more than the format
       * keeps, which is enough for the guard bit and a nonzero shift. */
      let k = fp_precision(single) + 2 + fp_int_bits(sigb) - fp_int_bits(siga);
      let num = if k >= 0 then siga * fp_pow2(k) else siga;
      let den = if k >= 0 then sigb else sigb * fp_pow2(0 - k);
      let q = tdiv_int(num, den);
      Ev_Number(sign, q, expa - expb - k, q * den != num)
    }
  }
}

/* --- Fused multiply-add (§2.5.1.1) -------------------------------------- */

/* (a * c) + b with a single rounding: both the product and the sum are
 * computed exactly here, so the "106 bits of the intermediate product take
 * part in the add" requirement is met by construction. */
val fp_fma_eval : (bits(64), bits(64), bits(64), bits(2)) -> FpEval
function fp_fma_eval(a, c, b, rn) = {
  let psign = xor_vec(fp_sign(a), fp_sign(c));
  if fp_is_nan(a) | fp_is_nan(b) | fp_is_nan(c) then fp_nan_result(a, b, c)
  else {
    let prod_invalid = (fp_is_inf(a) & fp_is_zero(c)) | (fp_is_zero(a) & fp_is_inf(c));
    let prod_inf = (fp_is_inf(a) | fp_is_inf(c)) & not_bool(prod_invalid);
    if prod_invalid then Ev_Invalid(fpscr_bit_vximz, fp_default_qnan)
    else if prod_inf then {
      /* An infinite product still has to face the addend. */
      if fp_is_inf(b) & (fp_sign(b) != psign) then
        Ev_Invalid(fpscr_bit_vxisi, fp_default_qnan)
      else Ev_Inf(psign)
    } else if fp_is_inf(b) then Ev_Inf(fp_sign(b))
    else {
      let (siga, expa) = fp_unpack(a);
      let (sigc, expc) = fp_unpack(c);
      let (sigb, expb) = fp_unpack(b);
      let psig = siga * sigc;
      let pexp = expa + expc;
      let e = min_int(pexp, expb);
      let vp = psig * fp_pow2(pexp - e);
      let vb = sigb * fp_pow2(expb - e);
      let sum = (if psign == 0b1 then 0 - vp else vp)
                + (if fp_sign(b) == 0b1 then 0 - vb else vb);
      if sum == 0 then {
        /* As for addition: a like-signed pair of zeros keeps its sign, and
         * an exact cancellation is positive except toward -infinity. */
        if (psig == 0) & (sigb == 0) & (psign == fp_sign(b)) then Ev_Zero(psign)
        else Ev_Zero(if rn == 0b11 then 0b1 else 0b0)
      } else if sum < 0 then Ev_Number(0b1, 0 - sum, e, false)
      else Ev_Number(0b0, sum, e, false)
    }
  }
}

/* Negate an evaluated result, for the two "negative multiply-add" forms.
 * A NaN is deliberately left alone: the ch. 10 fnmadd page lists exactly that
 * as the difference from negating the result afterwards — "QNaNs propagate
 * with no effect on their sign bit", a generated QNaN keeps its zero sign,
 * and a quietened SNaN keeps the SNaN's sign. */
val fp_negate_eval : FpEval -> FpEval
function fp_negate_eval(ev) = match ev {
  Ev_Invalid(mask, qnan)     => Ev_Invalid(mask, qnan),
  Ev_ZeroDivide(s)           => Ev_ZeroDivide(xor_vec(s, 0b1)),
  Ev_Inf(s)                  => Ev_Inf(xor_vec(s, 0b1)),
  Ev_Zero(s)                 => Ev_Zero(xor_vec(s, 0b1)),
  Ev_Number(s, sig, exp, st) => Ev_Number(xor_vec(s, 0b1), sig, exp, st)
}

/* --- Comparison (§3.4.4) ------------------------------------------------ */

/* Ordering of two operands, ignoring the sign of zero.  Returns the FPCC
 * encoding directly: FL, FG, FE, FU with exactly one bit set. */
val fp_compare : (bits(64), bits(64)) -> bits(4)
function fp_compare(a, b) = {
  if fp_is_nan(a) | fp_is_nan(b) then 0b0001            /* unordered */
  else {
    /* Compare as exact numbers; infinities are handled by giving them an
     * exponent above anything finite. */
    let (siga, expa) : (int, int) = if fp_is_inf(a) then (1, 100000) else fp_unpack(a);
    let (sigb, expb) : (int, int) = if fp_is_inf(b) then (1, 100000) else fp_unpack(b);
    let e = min_int(expa, expb);
    let va = siga * fp_pow2(expa - e);
    let vb = sigb * fp_pow2(expb - e);
    let sa = if fp_sign(a) == 0b1 then 0 - va else va;
    let sb = if fp_sign(b) == 0b1 then 0 - vb else vb;
    if sa < sb then 0b1000 else if sa > sb then 0b0100 else 0b0010
  }
}

/* --- Conversion to a 32-bit integer (§3.4.3, ch. 10 fctiw page) --------- */

/* The rounded integer, and whether the conversion was inexact / incremented.
 * `out_of_range` covers the operands the instruction has to clamp — an
 * infinity, a NaN, or a magnitude outside the 32-bit signed range — which
 * are also the invalid integer convert condition (VXCVI). */
struct FpToInt = {
  value       : bits(32),
  inexact     : bool,
  incremented : bool,
  invalid     : bool
}

val fp_to_int32 : (bits(64), bits(2)) -> FpToInt
function fp_to_int32(v, rn) = {
  if fp_is_nan(v) | fp_is_inf(v) then
    /* NaN and -infinity clamp low, +infinity clamps high (ch. 10 page). */
    struct { value = if fp_is_inf(v) & (fp_sign(v) == 0b0) then 0x7FFFFFFF
                     else 0x80000000,
             inexact = false, incremented = false, invalid = true }
  else {
    let (sig, exp) = fp_unpack(v);
    /* Split into an integer part and the fraction that rounding consumes. */
    let ip = if exp >= 0 then sig * fp_pow2(exp) else tdiv_int(sig, fp_pow2(0 - exp));
    let rem = if exp >= 0 then 0 else sig - ip * fp_pow2(0 - exp);
    let d = if exp >= 0 then 1 else fp_pow2(0 - exp);
    let half = tdiv_int(d, 2);
    let neg = fp_sign(v) == 0b1;
    let inexact = rem != 0;
    /* Round the MAGNITUDE, then apply the sign, so "toward +infinity" has to
     * look at the sign to decide which way that is. */
    let round_up : bool = match rn {
      0b00 => (rem > half) | ((rem == half) & (tmod_int(ip, 2) == 1)),
      0b01 => false,
      0b10 => inexact & not_bool(neg),
      _    => inexact & neg
    };
    let mag = if round_up then ip + 1 else ip;
    let signed_val = if neg then 0 - mag else mag;
    if (signed_val > 2147483647) | (signed_val < -2147483648) then
      struct { value = if neg then 0x80000000 else 0x7FFFFFFF,
               inexact = false, incremented = false, invalid = true }
    else
      struct { value = get_slice_int(32, signed_val, 0),
               inexact = inexact, incremented = round_up, invalid = false }
  }
}

$endif
