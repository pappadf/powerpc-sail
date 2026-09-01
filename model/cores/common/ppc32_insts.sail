/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc32_insts.sail — instructions the 603e, 604, 604e and 750 all have and
 * the 601 does not.  Each is either a facility the 601 predates (the time
 * base) or an optional instruction the 601 declines and all four of these
 * implement (MPC603EUM Tables 2-28/2-32, MPC604UM §2.3, MPC750UM §2.3):
 *
 *   mftb                      read the time base       (MPCFPE32B §2.3.12)
 *   tlbsync                   TLB synchronise          (MPCFPE32B §4.6.4.2)
 *   stfiwx                    store word from an FPR   (MPCFPE32B §4.6.3)
 *   fsel[.]                   floating select
 *   fres[.]                   reciprocal estimate
 *
 * NOT here, and deliberately absent so that they decode to ILLEGAL on every
 * core in this model:
 *   fsqrt[s]  — "the MPC750 provides hardware support for all instructions
 *               defined for 32-bit implementations.  It does not support the
 *               optional fsqrt, fsqrts and tlbia instructions" (MPC750UM
 *               §2.3.1; MPC604UM §2.3.1 and MPC603EUM §2.3.1.2 say the same),
 *               so this is the architected behaviour and not a gap;
 *   tlbia     — likewise absent from all four;
 *   frsqrte[.]— A GAP, not architected behaviour: all four cores implement it
 *               and this model does not, because it needs a square root
 *               kernel that ppc_softfloat.sail does not have and that fres
 *               below could not borrow.  See the README's known divergences.
 */

$ifndef _PPC32_INSTS
$define _PPC32_INSTS

/* --- mftb rD,TBR (XFX-form, XO=371) -------------------------------------- */

/* Reads the time base.  The TBR field is encoded exactly as mfspr's SPR field
 * is — two 5-bit halves, low-order first — so sprno_of_field un-swizzles both
 * (MPCFPE32B §8.2, and the mftb page).
 *
 * ONLY TBR 268 (TBL) AND 269 (TBU) ARE ACCEPTED, and the two are read here
 * rather than by delegating to read_spr.  Delegating would be shorter and is
 * wrong: mftb performs NO privilege check, because the time base is
 * user-readable by design ("the TB registers are read-only in user state",
 * MPC603EUM §2.1.1), so an mftb naming a supervisor SPR number would read
 * that register from user mode — SPR 22, the decrementer, being the obvious
 * one.  The architecture gives mftb its own small, entirely user-level value
 * space, and this keeps to it.
 *
 * Any other TBR is not implemented and no-ops, which is the same treatment
 * mfspr gives an unimplemented SPR (ppc_insts_system.sail).
 *
 * The 603e "ignores the extended opcode differences between mftb and mfspr by
 * ignoring TB[25] and treating both instructions identically" (MPC603EUM
 * Table 2-40 note).  That makes mftb and mfspr interchangeable there but not
 * on the 604 or 750, so the two are modelled as the distinct instructions the
 * architecture defines; the 603e's leniency accepts everything this accepts
 * and more, so nothing that runs on hardware is rejected here. */
union clause ast = MFTB : (ridx, bits(10))

mapping clause encdec =
  MFTB(rD, tbrf) <-> 0b011111 @ rD : ridx @ tbrf : bits(10) @ 0b0101110011 @ 0b0

function clause execute(MFTB(rD, tbrf)) = {
  match sprno_of_field(tbrf) {
    0b0100001100 /* 268 TBL */ => { GPR(rD) = TBL; COMPLETED },
    0b0100001101 /* 269 TBU */ => { GPR(rD) = TBU; COMPLETED },
    _ => COMPLETED
  }
}

/* --- tlbsync (X-form, XO=566) -------------------------------------------- */

/* Waits until every TLB invalidate broadcast by this processor has completed
 * on every other processor (MPCFPE32B §4.6.4.2).  This model has one
 * processor and no TLB, so — like tlbie and sync — there is nothing to wait
 * for and the instruction is a privileged no-op.  Supervisor-level on all
 * four cores (MPC603EUM §2.3.1.3's list of supervisor instructions). */
union clause ast = TLBSYNC : unit

mapping clause encdec =
  TLBSYNC() <-> 0b011111 @ 0b00000 @ 0b00000 @ 0b00000 @ 0b1000110110 @ 0b0

function clause execute(TLBSYNC()) =
  if in_user_mode() then program_exception(Prog_Privileged)
  else COMPLETED

/* --- stfiwx frS,rA,rB (X-form, XO=983) ----------------------------------- */

/* Stores the LOW WORD of frS with no conversion at all — "the contents of the
 * low-order 32 bits of frS are stored, without conversion, into the word in
 * memory addressed by EA" (MPCFPE32B §4.6.3).  It is the inverse of fctiw,
 * whose result is exactly such a low word, and the pair is how an integer
 * leaves the floating-point registers.
 *
 * Deliberately NOT exec_fp_store with width 4: that converts double to single
 * format, which is the opposite of what this instruction is for.  There is no
 * update form.
 *
 * UNDEF: "if the contents of frS were not produced by fctiw, fctiwz or one of
 * the load-integer instructions, the value stored is undefined" — the value
 * this model stores is simply the low word whatever produced it, which is
 * what the hardware does and is a superset of the defined cases. */
union clause ast = STFIWX : (fridx, ridx, ridx)

mapping clause encdec =
  STFIWX(frS, rA, rB) <->
    0b011111 @ frS : fridx @ rA : ridx @ rB : ridx @ 0b1111010111 @ 0b0

function clause execute(STFIWX(frS, rA, rB)) =
  if fp_unavailable() then fp_unavailable_exception()
  else {
    let ea = ea_x(rA, rB);
    if mem_write_fp(ea, 4, FPR(frS)[31 .. 0]) then COMPLETED
    else EXCEPTION_TAKEN
  }

/* --- fsel frD,frA,frC,frB (A-form, XO=23) -------------------------------- */

/* frD = if frA >= 0 and frA is not a NaN then frC else frB.
 *
 * A SELECT, not a comparison: "this instruction may be used to implement
 * floating-point minimum and maximum functions ... the comparison ignores the
 * sign of zero, so +0 and -0 both select frC" (MPCFPE32B §4.6.5, and the
 * warning that it must not be used where the difference between a NaN and a
 * negative number matters).  Hence the test is on the VALUE and not on the
 * sign bit: -0.0 has the sign bit set and still selects frC.
 *
 * No FPSCR effect and no exception, not even for an SNaN — the instruction
 * examines frA without operating on it, exactly as the sign-manipulation
 * moves do (exec_fp_move, ppc_insts_fp.sail).  Rc = 1 still copies the
 * unchanged summary bits into CR1. */
union clause ast = FSEL : (fridx, fridx, fridx, fridx, bits(1))

mapping clause encdec =
  FSEL(frD, frA, frC, frB, rc) <->
    0b111111 @ frD : fridx @ frA : fridx @ frB : fridx @ frC : fridx
            @ 0b10111 @ rc : bits(1)

function clause execute(FSEL(frD, frA, frC, frB, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else {
    let a = FPR(frA);
    /* "frA >= 0 and frA is not a NaN".  fp_is_zero covers both signed zeros,
     * which is what makes -0.0 select frC. */
    let take_c = not_bool(fp_is_nan(a))
                 & ((fp_sign(a) == 0b0) | fp_is_zero(a));
    FPR(frD) = if take_c then FPR(frC) else FPR(frB);
    fp_set_cr1(rc);
    COMPLETED
  }

/* --- fres frD,frB (A-form, opcode 59, XO=24) ----------------------------- */

/* A single-precision estimate of 1/frB.
 *
 * MODEL CHOICE.  The architecture requires only that the estimate be within
 * one part in 256 of the exact reciprocal — "the value placed into frD may
 * vary between implementations, and between different executions on the same
 * implementation" (MPCFPE32B §4.6.6) — so no model can be bit-accurate to
 * silicon and this one does not try.  It computes the CORRECTLY ROUNDED
 * single-precision reciprocal, which satisfies the accuracy requirement with
 * room to spare and is reproducible, by reusing the divide evaluator with a
 * numerator of one.
 *
 * Doing it that way is not just convenient: every special case fres defines
 * falls out of division by construction and cannot drift from it —
 *   frB = ±0   -> ±Infinity, and ZX set   (1/±0 is a zero divide),
 *   frB = ±Inf -> ±0                      (finite/Inf is a zero),
 *   frB = SNaN -> QNaN, and VXSNAN set,
 *   frB = QNaN -> that QNaN, propagated,
 * which is exactly Table 4-6's list for fres.  The one place the two differ
 * is FPSCR[FI] and [FR], which the architecture leaves UNDEFINED for fres and
 * which this instruction therefore sets as a divide would; "undefined" is
 * modelled as "whatever the shared path produces" throughout this model.
 *
 * Note the opcode: 59 (single-precision), so the result is rounded to single
 * precision and delivered in double format, as fdivs does. */
union clause ast = FRES : (fridx, fridx, bits(1))

mapping clause encdec =
  FRES(frD, frB, rc) <->
    0b111011 @ frD : fridx @ 0b00000 @ frB : fridx @ 0b00000 @ 0b11000 @ rc : bits(1)

/* 1.0 in double format, the numerator of the reciprocal. */
let fp_one : bits(64) = 0x3FF0000000000000

function clause execute(FRES(frD, frB, rc)) =
  if fp_unavailable() then fp_unavailable_exception()
  else fp_deliver(frD, fp_div_eval(fp_one, FPR(frB), true), true, rc)

$endif
