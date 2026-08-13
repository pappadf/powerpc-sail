/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_insts_fp.sail — floating-point instructions (MPC601UM §3.4, §3.5.8-11,
 * ch. 10).  The arithmetic itself is in ppc_softfloat.sail; this file is
 * everything the ARCHITECTURE wraps around it — the MSR[FP] gate, the FPSCR
 * update rules of §5.4.7, the FPRF classification, CR1, and the instruction
 * encodings.
 *
 * IMPLEMENTED — the whole of the 601's floating-point set:
 *   lfs lfsx lfsu lfsux lfd lfdx lfdu lfdux      (Table 3-22)
 *   stfs stfsx stfsu stfsux stfd stfdx stfdu stfdux  (Table 3-23)
 *   fmr[.] fneg[.] fabs[.] fnabs[.]              (Table 3-24)
 *   fadd[s][.] fsub[s][.] fmul[s][.] fdiv[s][.]  (Table 3-10)
 *   fmadd[s][.] fmsub[s][.] fnmadd[s][.] fnmsub[s][.]  (Table 3-11)
 *   frsp[.] fctiw[.] fctiwz[.]                   (Table 3-12)
 *   fcmpu fcmpo                                  (Table 3-14)
 *   mffs[.] mcrfs mtfsfi[.] mtfsf[.] mtfsb0[.] mtfsb1[.]  (Table 3-15)
 *
 * NOT ON THE 601 (Table 10-6), and deliberately absent so that they decode to
 * ILLEGAL: fsqrt[s], fres, frsqrte, fsel, stfiwx.
 *
 * THREE RULES RUN THROUGH EVERYTHING HERE:
 *
 *  - MSR[FP] = 0 makes every floating-point instruction — including the
 *    loads, stores and moves — take a floating-point unavailable exception
 *    (§5.4.8).  fp_unavailable below is that check.
 *  - Rc = 1 does NOT set CR0; it copies FPSCR[FX FEX VX OX] into CR1
 *    (§2.2.4.2).
 *  - An instruction that leaves FPSCR[FEX] set takes a program exception
 *    afterwards if MSR[FE0] or MSR[FE1] is set, and on the 601 that is always
 *    precise (§5.4.7.1).  fp_finish applies it after the result is written,
 *    because "whether a floating-point result is stored and what value is
 *    stored ... are not affected by any MSR bit settings".
 */

$ifndef _PPC_INSTS_FP
$define _PPC_INSTS_FP

/* --- FPSCR maintenance (§2.2.3) ----------------------------------------- */

/* Bits the 601's FPSCR does not implement: manual bit 20, VXSOFT (21),
 * VXSQRT (22) and bit 29, all of which read as zero (Table 2-1). */
let fpscr_implemented : word = 0xFFFFF1FB

/* The sticky exception bits, whose 0 -> 1 transition sets FX: manual bits
 * 3-12 (OX..VXVC) and 21-23, of which the 601 has only VXCVI (23). */
let fpscr_exception_bits : word = 0x1FF80100

/* The invalid-operation bits that VX summarizes: manual bits 7-12, 21-23. */
let fpscr_invalid_bits : word = 0x01F80100

/* FEX and VX are not stored but derived — "the logical ORs of other FPSCR
 * bits" (§2.2.3) — so every write recomputes them rather than keeping them. */
val fpscr_update_summary : unit -> unit
function fpscr_update_summary() = {
  let vx = (FPSCR.bits & fpscr_invalid_bits) != zeros(32);
  FPSCR[VX] = bool_to_bits(vx);
  FPSCR[FEX] = bool_to_bits(
    (vx & (FPSCR[VE] == 0b1))
    | ((FPSCR[OX] == 0b1) & (FPSCR[OE] == 0b1))
    | ((FPSCR[UX] == 0b1) & (FPSCR[UE] == 0b1))
    | ((FPSCR[ZX] == 0b1) & (FPSCR[ZE] == 0b1))
    | ((FPSCR[XX] == 0b1) & (FPSCR[XE] == 0b1)))
}

/* Raise exception bits, applying the FX rule: "every floating-point
 * instruction implicitly sets FPSCR[FX] if that instruction causes any of the
 * floating-point exception bits to transition from 0 to 1" (§2.2.3).  Note
 * that it is the TRANSITION that matters, so raising an already-set sticky
 * bit leaves FX alone. */
val fpscr_raise : word -> unit
function fpscr_raise(m) = {
  let raised = m & fpscr_implemented;
  let newly = raised & not_vec(FPSCR.bits) & fpscr_exception_bits;
  FPSCR = Mk_Fpscr(FPSCR.bits | raised);
  if newly != zeros(32) then FPSCR[FX] = 0b1;
  fpscr_update_summary()
}

/* A whole-FPSCR write (the mtfsf family): the value lands as given, FX
 * included, and only the two derived bits are recomputed (§3.4.5). */
val fpscr_write : word -> unit
function fpscr_write(v) = {
  FPSCR = Mk_Fpscr(v & fpscr_implemented);
  fpscr_update_summary()
}

val fpscr_set_fr_fi : (bool, bool) -> unit
function fpscr_set_fr_fi(fr, fi) = {
  FPSCR[FR] = bool_to_bits(fr);
  FPSCR[FI] = bool_to_bits(fi)
}

/* FPRF (Table 2-2): C || FL FG FE FU, "based on the value placed into the
 * target register even if that value is undefined". */
val fp_class_fprf : bits(64) -> bits(5)
function fp_class_fprf(v) = {
  let neg = fp_sign(v) == 0b1;
  match fp_kind(v) {
    FK_QNaN => 0b10001,
    FK_SNaN => 0b10001,
    FK_Inf  => if neg then 0b01001 else 0b00101,
    FK_Zero => if neg then 0b10010 else 0b00010,
    FK_Finite =>
      /* denormalized numbers are the ones with a zero biased exponent */
      if v[62 .. 52] == zeros(11) then (if neg then 0b11000 else 0b10100)
      else (if neg then 0b01000 else 0b00100)
  }
}

val fpscr_set_fprf : bits(64) -> unit
function fpscr_set_fprf(v) = { FPSCR[FPRF] = fp_class_fprf(v) }

/* --- The three wrappers every floating-point instruction uses ----------- */

/* MSR[FP] = 0: floating-point unavailable, for loads and stores and moves as
 * much as for arithmetic (§5.4.8). */
val fp_unavailable : unit -> bool
function fp_unavailable() = MSR[FP] == 0b0

/* Rc = 1 copies the FPSCR's four summary/status bits into CR1 (§2.2.4.2). */
val fp_set_cr1 : bits(1) -> unit
function fp_set_cr1(rc) =
  if rc == 0b1 then CRfield(1, FPSCR.bits[31 .. 28])

/* Which exception bits currently have their enable bit set.  FEX is the OR
 * of exactly these (§2.2.3), and they are also what decides whether an
 * instruction invokes the handler. */
val fpscr_enabled_mask : unit -> word
function fpscr_enabled_mask() =
  (if FPSCR[VE] == 0b1 then fpscr_invalid_bits else zeros(32))
  | (if FPSCR[OE] == 0b1 then 0x10000000 else zeros(32))   /* OX, manual 3 */
  | (if FPSCR[UE] == 0b1 then 0x08000000 else zeros(32))   /* UX, manual 4 */
  | (if FPSCR[ZE] == 0b1 then 0x04000000 else zeros(32))   /* ZX, manual 5 */
  | (if FPSCR[XE] == 0b1 then 0x02000000 else zeros(32))   /* XX, manual 6 */

/* Raise a set of exception bits and report whether any of them was enabled —
 * which is the condition that invokes the handler.  Note it is the RAISING
 * that counts, not FEX being set: §5.4.7 says the exception is generated by
 * "a floating-point instruction that CAUSES an enabled exception", so an
 * instruction that merely runs while an earlier enabled condition is still
 * outstanding does not take it again. */
val fpscr_raise_enabled : word -> bool
function fpscr_raise_enabled(m) = {
  let enabled = (m & fpscr_enabled_mask()) != zeros(32);
  fpscr_raise(m);
  enabled
}

/* The tail of every FPSCR-updating instruction: set CR1, then take the
 * program exception if this instruction caused an enabled exception and the
 * MSR lets it through (§5.4.7.1).  The 601 has no imprecise modes, so there
 * is no mode to distinguish — FE0 and FE1 are simply ORed.
 *
 * This runs AFTER the result has been written, because "whether a
 * floating-point result is stored and what value is stored is determined by
 * the FPSCR exception enable bits ... and are not affected by any MSR bit
 * settings" (§5.4.7.1). */
val fp_finish : (bool, bits(1)) -> Completion
function fp_finish(caused, rc) = {
  fp_set_cr1(rc);
  if caused & (FPSCR[FEX] == 0b1) & fp_exceptions_enabled() then
    program_exception(Prog_FPEnabled)
  else COMPLETED
}

/* --- Single-precision memory format (§3.5.9.1, §3.5.10.1) --------------- */

/* Memory single -> register double.  The manual gives this as three cases of
 * bit copying, and the only one that is not a copy is the denormalized
 * operand, which it states as a normalize loop: every single denormal is a
 * NORMAL double, so packing the exact value (fraction * 2^-149) does the same
 * job in one step.  No exception can arise (§2.5.5). */
val fp_single_to_double : bits(32) -> bits(64)
function fp_single_to_double(w) = {
  let sign : bits(1) = [w[31]];
  let e = w[30 .. 23];
  let f = w[22 .. 0];
  if (e == 0x00) & (f != zeros(23)) then fp_pack(sign, unsigned(f), -149)
  else {
    /* Normalized operands rebias by replacing the top exponent bit with
     * three copies of its complement; zero, infinity and NaN copy it. */
    let b : bits(1) = [w[30]];
    let fill = if (e != 0x00) & (e != 0xFF) then not_vec(b) else b;
    sign @ b @ replicate_bits(fill, 3) @ w[29 .. 0] @ zeros(29)
  }
}

/* Register double -> memory single.  Above the denormalization threshold the
 * exponent rebias is again pure bit copying; between manual exponents 874 and
 * 896 the significand is shifted right until the exponent reaches -126.
 *
 * UNDEF: below 874 the operand cannot be represented as a single at all, and
 * the manual defines no result — §2.5.5 says the stored value is "assumed to
 * be the result of" a single-precision operation.  Continuing the shift is
 * the natural reading and delivers a zero of the right sign, which is what
 * the shift below does for any exponent. */
val fp_double_to_single : bits(64) -> bits(32)
function fp_double_to_single(v) = {
  let be = unsigned(v[62 .. 52]);
  if (be > 896) | (v[62 .. 0] == zeros(63)) then
    [v[63]] @ [v[62]] @ v[58 .. 29]
  else {
    let frac : bits(53) = 0b1 @ v[51 .. 0];
    let shifted = sail_shiftright(frac, 897 - be);
    [v[63]] @ zeros(8) @ shifted[51 .. 29]
  }
}

/* --- Floating-point loads and stores (Tables 3-22/3-23) ----------------- */

/* Load `width` bytes into frD, converting from single format if width is 4,
 * then (for the update forms) write the effective address back to rA.
 *
 * INVALID-FORM (ch. 10 lfsu page): "if operand rA = 0 the 601 does not
 * update register r0" — the same asymmetry the integer loads and stores
 * have, and stated just as explicitly. */
val exec_fp_load : forall 'n, 'n in {4, 8}.
  (fridx, ridx, word, int('n), bool) -> Completion
function exec_fp_load(frD, rA, ea, width, update) =
  match mem_read_fp(ea, width) {
    Some(v) => {
      let x : bits(64) = sail_zero_extend(v, 64);
      FPR(frD) = if width == 4 then fp_single_to_double(x[31 .. 0]) else x;
      if update & (rA != 0b00000) then GPR(rA) = ea;
      COMPLETED
    },
    None() => EXCEPTION_TAKEN
  }

/* Store frS, converting to single format if width is 4.  As for the integer
 * stores, rA = 0 executes as written and r0 IS updated (ch. 10 stfdu page:
 * "the 601 supports execution with rA=0 as shown above"). */
val exec_fp_store : forall 'n, 'n in {4, 8}.
  (fridx, ridx, word, int('n), bool) -> Completion
function exec_fp_store(frS, rA, ea, width, update) = {
  let data : bits(64) = if width == 4 then sail_zero_extend(fp_double_to_single(FPR(frS)), 64)
                        else FPR(frS);
  if mem_write_fp(ea, width, slice(data, 0, 8 * width)) then {
    if update then GPR(rA) = ea;
    COMPLETED
  } else EXCEPTION_TAKEN
}

union clause ast = LFS : (fridx, ridx, bits(16), bool)   /* update form? */

mapping clause encdec =
  LFS(frD, rA, d, false) <-> 0b110000 @ frD : fridx @ rA : ridx @ d : bits(16)

mapping clause encdec =
  LFS(frD, rA, d, true)  <-> 0b110001 @ frD : fridx @ rA : ridx @ d : bits(16)

function clause execute(LFS(frD, rA, d, update)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fp_load(frD, rA, if update then ea_du(rA, d) else ea_d(rA, d), 4, update)

union clause ast = LFD : (fridx, ridx, bits(16), bool)

mapping clause encdec =
  LFD(frD, rA, d, false) <-> 0b110010 @ frD : fridx @ rA : ridx @ d : bits(16)

mapping clause encdec =
  LFD(frD, rA, d, true)  <-> 0b110011 @ frD : fridx @ rA : ridx @ d : bits(16)

function clause execute(LFD(frD, rA, d, update)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fp_load(frD, rA, if update then ea_du(rA, d) else ea_d(rA, d), 8, update)

union clause ast = STFS : (fridx, ridx, bits(16), bool)

mapping clause encdec =
  STFS(frS, rA, d, false) <-> 0b110100 @ frS : fridx @ rA : ridx @ d : bits(16)

mapping clause encdec =
  STFS(frS, rA, d, true)  <-> 0b110101 @ frS : fridx @ rA : ridx @ d : bits(16)

function clause execute(STFS(frS, rA, d, update)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fp_store(frS, rA, if update then ea_du(rA, d) else ea_d(rA, d), 4, update)

union clause ast = STFD : (fridx, ridx, bits(16), bool)

mapping clause encdec =
  STFD(frS, rA, d, false) <-> 0b110110 @ frS : fridx @ rA : ridx @ d : bits(16)

mapping clause encdec =
  STFD(frS, rA, d, true)  <-> 0b110111 @ frS : fridx @ rA : ridx @ d : bits(16)

function clause execute(STFD(frS, rA, d, update)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fp_store(frS, rA, if update then ea_du(rA, d) else ea_d(rA, d), 8, update)

/* The indexed forms, whose four XO values differ only in the update and
 * precision bits (Table 3-22/3-23). */
union clause ast = LFSX : (fridx, ridx, ridx, bool)

mapping clause encdec =
  LFSX(frD, rA, rB, false) <->
    0b011111 @ frD : fridx @ rA : ridx @ rB : ridx @ 0b1000010111 @ 0b0

mapping clause encdec =
  LFSX(frD, rA, rB, true) <->
    0b011111 @ frD : fridx @ rA : ridx @ rB : ridx @ 0b1000110111 @ 0b0

function clause execute(LFSX(frD, rA, rB, update)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fp_load(frD, rA, if update then ea_xu(rA, rB) else ea_x(rA, rB), 4, update)

union clause ast = LFDX : (fridx, ridx, ridx, bool)

mapping clause encdec =
  LFDX(frD, rA, rB, false) <->
    0b011111 @ frD : fridx @ rA : ridx @ rB : ridx @ 0b1001010111 @ 0b0

mapping clause encdec =
  LFDX(frD, rA, rB, true) <->
    0b011111 @ frD : fridx @ rA : ridx @ rB : ridx @ 0b1001110111 @ 0b0

function clause execute(LFDX(frD, rA, rB, update)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fp_load(frD, rA, if update then ea_xu(rA, rB) else ea_x(rA, rB), 8, update)

union clause ast = STFSX : (fridx, ridx, ridx, bool)

mapping clause encdec =
  STFSX(frS, rA, rB, false) <->
    0b011111 @ frS : fridx @ rA : ridx @ rB : ridx @ 0b1010010111 @ 0b0

mapping clause encdec =
  STFSX(frS, rA, rB, true) <->
    0b011111 @ frS : fridx @ rA : ridx @ rB : ridx @ 0b1010110111 @ 0b0

function clause execute(STFSX(frS, rA, rB, update)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fp_store(frS, rA, if update then ea_xu(rA, rB) else ea_x(rA, rB), 4, update)

union clause ast = STFDX : (fridx, ridx, ridx, bool)

mapping clause encdec =
  STFDX(frS, rA, rB, false) <->
    0b011111 @ frS : fridx @ rA : ridx @ rB : ridx @ 0b1011010111 @ 0b0

mapping clause encdec =
  STFDX(frS, rA, rB, true) <->
    0b011111 @ frS : fridx @ rA : ridx @ rB : ridx @ 0b1011110111 @ 0b0

function clause execute(STFDX(frS, rA, rB, update)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fp_store(frS, rA, if update then ea_xu(rA, rB) else ea_x(rA, rB), 8, update)

/* --- Floating-point moves (Table 3-24) ---------------------------------- */

/* Pure bit manipulation on the sign: no FPSCR effect at all, not even FPRF,
 * and no exception — "these instructions do not modify the FPSCR", and a
 * move is not an operation on an SNaN for §5.4.7.2's purposes.  Rc=1 still
 * copies the (unchanged) FPSCR summary bits into CR1. */
val exec_fp_move : (fridx, bits(64), bits(1)) -> Completion
function exec_fp_move(frD, v, rc) = {
  FPR(frD) = v;
  fp_set_cr1(rc);
  COMPLETED
}

union clause ast = FMR : (fridx, fridx, bits(1))

mapping clause encdec =
  FMR(frD, frB, rc) <->
    0b111111 @ frD : fridx @ 0b00000 @ frB : fridx @ 0b0001001000 @ rc : bits(1)

function clause execute(FMR(frD, frB, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fp_move(frD, FPR(frB), rc)

union clause ast = FNEG : (fridx, fridx, bits(1))

mapping clause encdec =
  FNEG(frD, frB, rc) <->
    0b111111 @ frD : fridx @ 0b00000 @ frB : fridx @ 0b0000101000 @ rc : bits(1)

function clause execute(FNEG(frD, frB, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fp_move(frD, xor_vec(FPR(frB), 0x8000000000000000), rc)

union clause ast = FABS : (fridx, fridx, bits(1))

mapping clause encdec =
  FABS(frD, frB, rc) <->
    0b111111 @ frD : fridx @ 0b00000 @ frB : fridx @ 0b0100001000 @ rc : bits(1)

function clause execute(FABS(frD, frB, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fp_move(frD, FPR(frB) & 0x7FFFFFFFFFFFFFFF, rc)

union clause ast = FNABS : (fridx, fridx, bits(1))

mapping clause encdec =
  FNABS(frD, frB, rc) <->
    0b111111 @ frD : fridx @ 0b00000 @ frB : fridx @ 0b0010001000 @ rc : bits(1)

function clause execute(FNABS(frD, frB, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fp_move(frD, FPR(frB) | 0x8000000000000000, rc)

/* --- Delivering an arithmetic result (§5.4.7) --------------------------- */

/* The remaining FPSCR exception bits, in FPSCR bit positions. */
let fpscr_bit_ox : bits(32) = 0x10000000   /* manual bit 3 */
let fpscr_bit_ux : bits(32) = 0x08000000   /* manual bit 4 */
let fpscr_bit_zx : bits(32) = 0x04000000   /* manual bit 5 */
let fpscr_bit_xx : bits(32) = 0x02000000   /* manual bit 6 */

/* Where an enabled overflow or underflow moves the exponent to (§5.4.7.4.1,
 * §5.4.7.5.1): the handler is expected to undo the bias, and the constant
 * differs by format because the exponent ranges do. */
val fp_scale_bias : bool -> int
function fp_scale_bias(single) = if single then 192 else 1536

/* The result a DISABLED overflow delivers, which depends on the rounding
 * mode as well as the sign (§5.4.7.4.1): round-to-nearest goes to infinity,
 * round-to-zero to the largest finite, and the two directed modes to
 * whichever of the two lies the way they round. */
val fp_overflow_result : (bits(1), bits(2), bool) -> bits(64)
function fp_overflow_result(sign, rn, single) = {
  let to_inf : bool = match rn {
    0b00 => true,
    0b01 => false,
    0b10 => sign == 0b0,
    _    => sign == 0b1
  };
  if to_inf then fp_infinity(sign) else fp_max_finite(sign, single)
}

/* Write the result of one arithmetic instruction, applying §5.4.7's rules.
 *
 * Two conditions SUPPRESS the write entirely — an enabled invalid operation
 * and an enabled zero divide — "so that there is no possibility that one of
 * the operands is lost"; every other condition delivers a result, and for
 * overflow and underflow the ENABLED result differs from the disabled one by
 * having its exponent scaled rather than by being clamped. */
val fp_deliver : (fridx, FpEval, bool, bits(1)) -> Completion
function fp_deliver(frD, ev, single, rc) = {
  let rn = FPSCR[RN];
  match ev {
    /* An empty mask means no invalid operation occurred at all: the operand
     * was already a quiet NaN and is simply propagating, so VE has no say. */
    Ev_Invalid(mask, qnan) => {
      let suppress = (mask != zeros(32)) & (FPSCR[VE] == 0b1);
      let caused = fpscr_raise_enabled(mask);
      fpscr_set_fr_fi(false, false);
      if not_bool(suppress) then {
        FPR(frD) = qnan;
        fpscr_set_fprf(qnan)
      };
      fp_finish(caused, rc)
    },
    Ev_ZeroDivide(sign) => {
      let suppress = FPSCR[ZE] == 0b1;
      let caused = fpscr_raise_enabled(fpscr_bit_zx);
      fpscr_set_fr_fi(false, false);
      if not_bool(suppress) then {
        FPR(frD) = fp_infinity(sign);
        fpscr_set_fprf(fp_infinity(sign))
      };
      fp_finish(caused, rc)
    },
    Ev_Inf(sign) => {
      FPR(frD) = fp_infinity(sign);
      fpscr_set_fr_fi(false, false);
      fpscr_set_fprf(fp_infinity(sign));
      fp_finish(false, rc)
    },
    Ev_Zero(sign) => {
      let z : bits(64) = sign @ zeros(63);
      FPR(frD) = z;
      fpscr_set_fr_fi(false, false);
      fpscr_set_fprf(z);
      fp_finish(false, rc)
    },
    Ev_Number(sign, sig, exp, sticky) => {
      let r = fp_round(sign, sig, exp, sticky, single, rn, false);
      var mask : word = zeros(32);
      var fr : bool = r.incremented;
      var fi : bool = r.inexact;
      var value : bits(64) = fp_pack(r.sign, r.sig, r.exp);
      if r.overflow then {
        mask = fpscr_bit_ox;
        if FPSCR[OE] == 0b1 then {
          /* Enabled: the rounded result with its exponent brought back into
           * range, so the handler sees a number rather than an infinity. */
          value = fp_pack(r.sign, r.sig, r.exp - fp_scale_bias(single));
          if r.inexact then mask = mask | fpscr_bit_xx
        } else {
          /* Disabled: the result is clamped, and is inexact by construction —
           * it is not the value the operation produced.  FI says so and FR
           * is cleared, there being no "incremented fraction" in a result
           * that was replaced wholesale.
           *
           * The manual states this twice and differently: Tables 2-1 and
           * 5-17 define FI as set by "an inexact fraction OR A DISABLED
           * EXPONENT OVERFLOW", while §5.4.7.4.1's action list says FR and
           * FI are both cleared.  The bit definition wins — it is the
           * normative statement of what FI means, its carve-out would be
           * pointless if the action list governed, and §5.4.7.4.1 sets the
           * sticky XX in the same breath as clearing the non-sticky FI,
           * which cannot both describe the same result. */
          mask = mask | fpscr_bit_xx;
          fr = false;
          fi = true;
          value = fp_overflow_result(r.sign, rn, single)
        }
      } else if r.tiny & (r.inexact | (FPSCR[UE] == 0b1)) then {
        /* Tiny is detected BEFORE rounding, but with UE = 0 it is only an
         * underflow if accuracy was actually lost (§5.4.7.5). */
        mask = fpscr_bit_ux;
        if FPSCR[UE] == 0b1 then {
          /* Enabled: round as though the exponent range were unbounded — so
           * the result is normalized, not denormalized — and then scale. */
          let ru = fp_round(sign, sig, exp, sticky, single, rn, true);
          value = fp_pack(ru.sign, ru.sig, ru.exp + fp_scale_bias(single));
          fr = ru.incremented;
          fi = ru.inexact;
          if ru.inexact then mask = mask | fpscr_bit_xx
        } else
          mask = mask | fpscr_bit_xx
      } else if r.inexact then
        mask = fpscr_bit_xx;
      FPR(frD) = value;
      fpscr_set_fr_fi(fr, fi);
      fpscr_set_fprf(value);
      fp_finish(fpscr_raise_enabled(mask), rc)
    }
  }
}

/* --- Floating-point arithmetic (§3.4.1, Table 3-10) --------------------- */

/* Eight instructions in four pairs: each operation has a double-precision
 * form under opcode 63 and a single-precision one under opcode 59, differing
 * only in the precision and exponent range the result is rounded to — the
 * operands are read as doubles either way, and the result is stored as a
 * double either way (§2.5.5).  So `single` is a field of the ast and the two
 * encodings share a clause.
 *
 * INVALID-FORM: a single-precision instruction whose operands are not
 * representable as singles has an undefined result (§2.5.5).  Nothing
 * special is done for it: the operation is carried out on the double
 * operands and rounded to single, which is deterministic and is what the
 * hardware's own datapath does. */
union clause ast = FADD : (fridx, fridx, fridx, bool, bits(1))

mapping clause encdec =
  FADD(frD, frA, frB, false, rc) <->
    0b111111 @ frD : fridx @ frA : fridx @ frB : fridx @ 0b00000 @ 0b10101 @ rc : bits(1)

mapping clause encdec =
  FADD(frD, frA, frB, true, rc) <->
    0b111011 @ frD : fridx @ frA : fridx @ frB : fridx @ 0b00000 @ 0b10101 @ rc : bits(1)

function clause execute(FADD(frD, frA, frB, single, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else fp_deliver(frD, fp_add_eval(FPR(frA), FPR(frB), FPSCR[RN]), single, rc)

/* fsub is fadd with frB's sign inverted (ch. 10 fsub page), but the flip must
 * not reach a NaN operand: §2.5.2.7 propagates frB's NaN as it stands, and
 * negating it would corrupt the sign the manual says to keep. */
union clause ast = FSUB : (fridx, fridx, fridx, bool, bits(1))

mapping clause encdec =
  FSUB(frD, frA, frB, false, rc) <->
    0b111111 @ frD : fridx @ frA : fridx @ frB : fridx @ 0b00000 @ 0b10100 @ rc : bits(1)

mapping clause encdec =
  FSUB(frD, frA, frB, true, rc) <->
    0b111011 @ frD : fridx @ frA : fridx @ frB : fridx @ 0b00000 @ 0b10100 @ rc : bits(1)

function clause execute(FSUB(frD, frA, frB, single, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else {
    let a = FPR(frA);
    let b = FPR(frB);
    let ev = if fp_is_nan(a) | fp_is_nan(b) then fp_nan_result(a, b, fp_default_qnan)
             else fp_add_eval(a, xor_vec(b, 0x8000000000000000), FPSCR[RN]);
    fp_deliver(frD, ev, single, rc)
  }

/* fmul takes its second operand from frC, not frB — the multiplier field the
 * multiply-add instructions use — and the frB field is reserved. */
union clause ast = FMUL : (fridx, fridx, fridx, bool, bits(1))

mapping clause encdec =
  FMUL(frD, frA, frC, false, rc) <->
    0b111111 @ frD : fridx @ frA : fridx @ 0b00000 @ frC : fridx @ 0b11001 @ rc : bits(1)

mapping clause encdec =
  FMUL(frD, frA, frC, true, rc) <->
    0b111011 @ frD : fridx @ frA : fridx @ 0b00000 @ frC : fridx @ 0b11001 @ rc : bits(1)

function clause execute(FMUL(frD, frA, frC, single, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else fp_deliver(frD, fp_mul_eval(FPR(frA), FPR(frC)), single, rc)

union clause ast = FDIV : (fridx, fridx, fridx, bool, bits(1))

mapping clause encdec =
  FDIV(frD, frA, frB, false, rc) <->
    0b111111 @ frD : fridx @ frA : fridx @ frB : fridx @ 0b00000 @ 0b10010 @ rc : bits(1)

mapping clause encdec =
  FDIV(frD, frA, frB, true, rc) <->
    0b111011 @ frD : fridx @ frA : fridx @ frB : fridx @ 0b00000 @ 0b10010 @ rc : bits(1)

function clause execute(FDIV(frD, frA, frB, single, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else fp_deliver(frD, fp_div_eval(FPR(frA), FPR(frB), single), single, rc)

/* --- Multiply-add (§3.4.2, Table 3-11) ---------------------------------- */

/* Four operations in eight instructions: (frA * frC) ± frB, optionally
 * negated, with ONE rounding — "the computation of the sum and product
 * together are infinitely precise before the final result is rounded"
 * (§2.5.1.1), which the exact-integer kernel gives for nothing.
 *
 * Both sign flips have to keep clear of NaN operands and NaN results.  A
 * subtract inverts frB's sign, which would corrupt a NaN that §2.5.2.7 says
 * to propagate unchanged, so the NaN case is taken first; and the negating
 * forms leave a NaN result alone, which is the whole of the ch. 10 fnmadd
 * page's list of differences from "fmadd, then negate". */
val exec_fma : (fridx, fridx, fridx, fridx, bool, bool, bool, bits(1)) -> Completion
function exec_fma(frD, frA, frC, frB, subtract, negate, single, rc) = {
  let a = FPR(frA);
  let b = FPR(frB);
  let c = FPR(frC);
  let ev = if fp_is_nan(a) | fp_is_nan(b) | fp_is_nan(c) then fp_nan_result(a, b, c)
           else fp_fma_eval(a, c,
                            if subtract then xor_vec(b, 0x8000000000000000) else b,
                            FPSCR[RN]);
  fp_deliver(frD, if negate then fp_negate_eval(ev) else ev, single, rc)
}

union clause ast = FMADD : (fridx, fridx, fridx, fridx, bool, bool, bool, bits(1))
                           /* frD, frA, frC, frB, subtract, negate, single, Rc */

mapping clause encdec =
  FMADD(frD, frA, frC, frB, false, false, false, rc) <->
    0b111111 @ frD : fridx @ frA : fridx @ frB : fridx @ frC : fridx @ 0b11101 @ rc : bits(1)

mapping clause encdec =
  FMADD(frD, frA, frC, frB, false, false, true, rc) <->
    0b111011 @ frD : fridx @ frA : fridx @ frB : fridx @ frC : fridx @ 0b11101 @ rc : bits(1)

mapping clause encdec =
  FMADD(frD, frA, frC, frB, true, false, false, rc) <->
    0b111111 @ frD : fridx @ frA : fridx @ frB : fridx @ frC : fridx @ 0b11100 @ rc : bits(1)

mapping clause encdec =
  FMADD(frD, frA, frC, frB, true, false, true, rc) <->
    0b111011 @ frD : fridx @ frA : fridx @ frB : fridx @ frC : fridx @ 0b11100 @ rc : bits(1)

mapping clause encdec =
  FMADD(frD, frA, frC, frB, false, true, false, rc) <->
    0b111111 @ frD : fridx @ frA : fridx @ frB : fridx @ frC : fridx @ 0b11111 @ rc : bits(1)

mapping clause encdec =
  FMADD(frD, frA, frC, frB, false, true, true, rc) <->
    0b111011 @ frD : fridx @ frA : fridx @ frB : fridx @ frC : fridx @ 0b11111 @ rc : bits(1)

mapping clause encdec =
  FMADD(frD, frA, frC, frB, true, true, false, rc) <->
    0b111111 @ frD : fridx @ frA : fridx @ frB : fridx @ frC : fridx @ 0b11110 @ rc : bits(1)

mapping clause encdec =
  FMADD(frD, frA, frC, frB, true, true, true, rc) <->
    0b111011 @ frD : fridx @ frA : fridx @ frB : fridx @ frC : fridx @ 0b11110 @ rc : bits(1)

function clause execute(FMADD(frD, frA, frC, frB, subtract, negate, single, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fma(frD, frA, frC, frB, subtract, negate, single, rc)

/* --- Rounding and conversion (§3.4.3, Table 3-12) ----------------------- */

/* frsp[.] frD,frB (XO=12): round a double to single precision and store it
 * back as a double.  It is an arithmetic instruction for every other
 * purpose — an SNaN operand is invalid, the result can overflow, underflow
 * or be inexact — so it is the identity operation delivered in the single
 * format, and fp_deliver's single-precision path does the rest, including
 * §5.4.7.4.1's 192 rather than 1536 for an enabled overflow. */
union clause ast = FRSP : (fridx, fridx, bits(1))

mapping clause encdec =
  FRSP(frD, frB, rc) <->
    0b111111 @ frD : fridx @ 0b00000 @ frB : fridx @ 0b0000001100 @ rc : bits(1)

function clause execute(FRSP(frD, frB, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else {
    let b = FPR(frB);
    let ev = if fp_is_nan(b) then fp_nan_result(b, fp_default_qnan, fp_default_qnan)
             else if fp_is_inf(b) then Ev_Inf(fp_sign(b))
             else if fp_is_zero(b) then Ev_Zero(fp_sign(b))
             else {
               let (sig, exp) = fp_unpack(b);
               Ev_Number(fp_sign(b), sig, exp, false)
             };
    fp_deliver(frD, ev, true, rc)
  }

/* fctiw[.] / fctiwz[.] frD,frB (XO=14 / 15): convert to a 32-bit signed
 * integer, under FPSCR[RN] or forced toward zero.  The 601 fills the
 * undefined high half of frD with x'FFF80000', which makes the register read
 * as a QNaN (§2.5.2.7, §3.4.3).
 *
 * UNDEF: "except for trap-enabled invalid operation exceptions, FPSCR[FPRF]
 * is undefined" — left unchanged here.
 *
 * The two statements of what an invalid convert delivers disagree, and the
 * specific one wins: §5.4.7.2.1 says the target gets "the most negative
 * 32-bit integer", while the ch. 10 page and Table 3-12 say an operand above
 * 2^31-1 gives x'7FFFFFFF' and one below -2^31 gives x'80000000'.  The
 * clamping direction is what the ch. 10 page is about, so that is what
 * fp_to_int32 implements; a NaN clamps low either way. */
val exec_fctiw : (fridx, fridx, bits(2), bits(1)) -> Completion
function exec_fctiw(frD, frB, rn, rc) = {
  let b = FPR(frB);
  let r = fp_to_int32(b, rn);
  let mask : word =
    if r.invalid then
      0x00000100 | (if fp_any_snan(b, fp_default_qnan, fp_default_qnan)
                    then fpscr_bit_vxsnan else zeros(32))   /* VXCVI, manual 23 */
    else if r.inexact then fpscr_bit_xx
    else zeros(32);
  /* An enabled invalid operation suppresses the write, as for arithmetic. */
  let suppress = r.invalid & (FPSCR[VE] == 0b1);
  let caused = fpscr_raise_enabled(mask);
  if r.invalid then fpscr_set_fr_fi(false, false)
  else fpscr_set_fr_fi(r.incremented, r.inexact);
  if not_bool(suppress) then FPR(frD) = 0xFFF80000 @ r.value;
  fp_finish(caused, rc)
}

union clause ast = FCTIW : (fridx, fridx, bool, bits(1))   /* toward zero? */

mapping clause encdec =
  FCTIW(frD, frB, false, rc) <->
    0b111111 @ frD : fridx @ 0b00000 @ frB : fridx @ 0b0000001110 @ rc : bits(1)

mapping clause encdec =
  FCTIW(frD, frB, true, rc) <->
    0b111111 @ frD : fridx @ 0b00000 @ frB : fridx @ 0b0000001111 @ rc : bits(1)

function clause execute(FCTIW(frD, frB, toward_zero, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fctiw(frD, frB, if toward_zero then 0b01 else FPSCR[RN], rc)

/* --- Floating-point compare (§3.4.4, Table 3-14) ------------------------ */

/* Both compares write the same four-bit result — one of FL, FG, FE, FU — to
 * the CR field named by crfD AND to FPSCR[FPCC], and both ignore the sign of
 * zero.  They differ only in what they make of a NaN operand:
 *
 *   fcmpu   a signaling NaN sets VXSNAN; a quiet one is merely unordered
 *   fcmpo   a signaling NaN sets VXSNAN, and VXVC too if VE = 0; a quiet
 *           NaN sets VXVC ("ordered comparison involving a NaN" is itself
 *           the invalid operation, §5.4.7.2)
 *
 * §5.4.7.2.1 adds that a compare leaves FPSCR[FR FI C] alone whatever
 * happens, which is why only the FPCC half of FPRF is written here.
 *
 * INVALID-FORM: bit 31 must be zero; the architecture calls CR1 and the crfD
 * field undefined if it is set (§3.4.4).  It decodes to ILLEGAL here, along
 * with every other reserved-field violation, where §5.4.7 asks for boundedly
 * undefined results instead — one divergence with one model-wide fix, noted
 * against the XO-form add/subtract family in ppc_insts_int.sail. */
let fpscr_bit_vxvc : bits(32) = 0x00080000   /* manual bit 12 */

val exec_fcmp : (cridx, fridx, fridx, bool) -> Completion
function exec_fcmp(crfd, frA, frB, ordered) = {
  let a = FPR(frA);
  let b = FPR(frB);
  let c = fp_compare(a, b);
  CRfield(unsigned(crfd), c);
  FPSCR[FPCC] = c;
  let snan = fp_any_snan(a, b, fp_default_qnan);
  let nan = fp_is_nan(a) | fp_is_nan(b);
  let raise : word =
    if not_bool(ordered) then (if snan then fpscr_bit_vxsnan else zeros(32))
    else if snan then
      fpscr_bit_vxsnan | (if FPSCR[VE] == 0b0 then fpscr_bit_vxvc else zeros(32))
    else if nan then fpscr_bit_vxvc
    else zeros(32);
  fp_finish(fpscr_raise_enabled(raise), 0b0)
}

union clause ast = FCMPU : (cridx, fridx, fridx)

mapping clause encdec =
  FCMPU(crfd, frA, frB) <->
    0b111111 @ crfd : cridx @ 0b00 @ frA : fridx @ frB : fridx @ 0b0000000000 @ 0b0

function clause execute(FCMPU(crfd, frA, frB)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fcmp(crfd, frA, frB, false)

union clause ast = FCMPO : (cridx, fridx, fridx)

mapping clause encdec =
  FCMPO(crfd, frA, frB) <->
    0b111111 @ crfd : cridx @ 0b00 @ frA : fridx @ frB : fridx @ 0b0000100000 @ 0b0

function clause execute(FCMPO(crfd, frA, frB)) =
  if fp_unavailable() then fp_unavailable_exception()
  else exec_fcmp(crfd, frA, frB, true)

/* --- FPSCR instructions (§3.4.5, Table 3-15) ---------------------------- */

/* These are the only instructions that write the FPSCR directly, and they
 * share one rule that the arithmetic does not: FX is whatever the written
 * value says, "even if this instruction causes OX to change from 0 to 1"
 * (§3.4.5), while FEX and VX are always recomputed.  fpscr_write does both.
 *
 * They invoke the handler on a different condition too — "a move to FPSCR
 * type instruction that SETS an exception bit when its corresponding enable
 * bit is set" (§5.4.7) — so what they report to fp_finish is the newly-set
 * enabled bits rather than the raised ones. */
val fpscr_write_caused : word -> bool
function fpscr_write_caused(old) =
  ((FPSCR.bits & not_vec(old)) & fpscr_exception_bits & fpscr_enabled_mask())
  != zeros(32)

/* mffs[.] frD (XO=583): the FPSCR into the low half of frD.  601: the high
 * half reads as all ones, where the architecture leaves it undefined
 * (Table 3-15) — which happens to make the result a QNaN (§2.5.2.7). */
union clause ast = MFFS : (fridx, bits(1))

mapping clause encdec =
  MFFS(frD, rc) <->
    0b111111 @ frD : fridx @ 0b00000 @ 0b00000 @ 0b1001000111 @ rc : bits(1)

function clause execute(MFFS(frD, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else {
    FPR(frD) = 0xFFFFFFFF @ FPSCR.bits;
    fp_finish(false, rc)
  }

/* mcrfs crfD,crfS (XO=64): copy an FPSCR field to a CR field, and clear the
 * exception bits that were copied — including FX when field 0 is the one
 * copied, which falls out of FX being one of them (§2.2.3).  FEX and VX are
 * not cleared directly but recomputed, so they go away exactly when the last
 * of their inputs does. */
union clause ast = MCRFS : (cridx, cridx)

mapping clause encdec =
  MCRFS(crfd, crfs) <->
    0b111111 @ crfd : cridx @ 0b00 @ crfs : cridx @ 0b00 @ 0b00000 @ 0b0001000000 @ 0b0

function clause execute(MCRFS(crfd, crfs)) =
  if fp_unavailable() then fp_unavailable_exception()
  else {
    let n = unsigned(crfs);
    let field = slice(FPSCR.bits, 28 - 4 * n, 4);
    CRfield(unsigned(crfd), field);
    /* the four bits of the copied field, as a whole-register mask */
    let field_mask = sail_shiftleft(0x0000000F, 28 - 4 * n);
    fpscr_write(FPSCR.bits & not_vec(field_mask & (fpscr_exception_bits | 0x80000000)));
    fp_finish(false, 0b0)
  }

/* mtfsfi[.] crfD,IMM (XO=134) and mtfsf[.] FM,frB (XO=711): write whole
 * four-bit fields.  mtfsf's FM selects which of the eight. */
union clause ast = MTFSFI : (cridx, bits(4), bits(1))

mapping clause encdec =
  MTFSFI(crfd, imm, rc) <->
    0b111111 @ crfd : cridx @ 0b00 @ 0b00000 @ imm : bits(4) @ 0b0
    @ 0b0010000110 @ rc : bits(1)

function clause execute(MTFSFI(crfd, imm, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else {
    let old = FPSCR.bits;
    let n = unsigned(crfd);
    fpscr_write(update_subrange_bits(old, 31 - 4 * n, 28 - 4 * n, imm));
    fp_finish(fpscr_write_caused(old), rc)
  }

union clause ast = MTFSF : (bits(8), fridx, bits(1))

mapping clause encdec =
  MTFSF(fm, frB, rc) <->
    0b111111 @ 0b0 @ fm : bits(8) @ 0b0 @ frB : fridx @ 0b1011000111 @ rc : bits(1)

function clause execute(MTFSF(fm, frB, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else {
    let old = FPSCR.bits;
    let src = FPR(frB)[31 .. 0];
    var v = old;
    /* FM bit i selects field i, and FM arrives msb-first: manual FM[0] is
     * sail fm[7] and selects field 0 (FPSCR bits 0-3). */
    foreach (i from 0 to 7) {
      if fm[7 - i] == bitone then
        v = update_subrange_bits(v, 31 - 4 * i, 28 - 4 * i,
                                 slice(src, 28 - 4 * i, 4))
    };
    fpscr_write(v);
    fp_finish(fpscr_write_caused(old), rc)
  }

/* mtfsb0[.] / mtfsb1[.] crbD (XO=70 / 38): clear or set one FPSCR bit, named
 * by its manual bit number.  "Bits 1 and 2 (FEX and VX) cannot be explicitly
 * reset" — they are derived, so writing them would be meaningless; the guard
 * below drops those two writes and lets the recompute stand.
 *
 * mtfsb1 goes through the ordinary raise path, so setting an exception bit
 * sets FX by the usual 0 -> 1 rule: the exemption §3.4.5 grants is stated
 * only for mtfsf and mtfsfi writing field 0. */
union clause ast = MTFSB0 : (bits(5), bits(1))

mapping clause encdec =
  MTFSB0(crbd, rc) <->
    0b111111 @ crbd : bits(5) @ 0b00000 @ 0b00000 @ 0b0001000110 @ rc : bits(1)

function clause execute(MTFSB0(crbd, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else {
    let n = unsigned(crbd);
    if (n != 1) & (n != 2) then
      fpscr_write(FPSCR.bits & not_vec(sail_shiftleft(0x00000001, 31 - n)));
    fp_finish(false, rc)
  }

union clause ast = MTFSB1 : (bits(5), bits(1))

mapping clause encdec =
  MTFSB1(crbd, rc) <->
    0b111111 @ crbd : bits(5) @ 0b00000 @ 0b00000 @ 0b0000100110 @ rc : bits(1)

function clause execute(MTFSB1(crbd, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else {
    let n = unsigned(crbd);
    let caused = if (n != 1) & (n != 2) then
                   fpscr_raise_enabled(sail_shiftleft(0x00000001, 31 - n))
                 else false;
    fp_finish(caused, rc)
  }

$endif
