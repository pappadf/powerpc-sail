/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_insts_branch.sail — branch and CR-logical instructions
 * (MPC601UM §3.6, ch. 10).
 *
 * IMPLEMENTED: b/ba/bl/bla (I-form), bc/bca/bcl/bcla (B-form, full BO/BI
 * condition evaluation with CTR decrement), bclr[l] / bcctr[l] (XL-form),
 * the eight CR-logical instructions and mcrf.
 */

$ifndef _PPC_INSTS_BRANCH
$define _PPC_INSTS_BRANCH

/* --- b/ba/bl/bla target (I-form: LI << 2, AA, LK) ----------------------- */

union clause ast = B : (bits(24), bits(1), bits(1))

mapping clause encdec =
  B(li, aa, lk) <-> 0b010010 @ li : bits(24) @ aa : bits(1) @ lk : bits(1)

function clause execute(B(li, aa, lk)) = {
  let offset : word = exts(li @ 0b00);
  if lk == 0b1 then { harness_wrote(hw_lr); LR = CIA + 4 };
  harness_wrote(hw_nia);
  NIA = if aa == 0b1 then offset else CIA + offset;
  COMPLETED
}

/* --- bc/bca/bcl/bcla BO,BI,target (B-form) ------------------------------ */

/* Condition evaluation per the ch. 10 bcx page:
 *   BO[0] (manual)  = 1: ignore CR bit BI
 *   BO[1]           = condition sense when BO[0]=0
 *   BO[2]           = 1: don't decrement/test CTR
 *   BO[3]           = CTR test sense when BO[2]=0
 *   BO[4]           = branch-prediction hint 'y' (no architectural effect)
 * BO arrives as bits(5) in manual bit order: BO[0] is bo[4] in sail. */
val branch_cond_taken : (bits(5), bits(5)) -> bool
function branch_cond_taken(bo, bi) = {
  let ctr_ok : bool =
    if bo[2] == bitone then true
    else {
      harness_wrote(hw_ctr);
      CTR = CTR - 1;
      /* BO[3]=1: branch if CTR=0; BO[3]=0: branch if CTR!=0 */
      if bo[1] == bitone then CTR == zeros(32) else CTR != zeros(32)
    };
  let cond_ok : bool =
    if bo[4] == bitone then true
    else CRbit(bi) == [bo[3]];
  ctr_ok & cond_ok
}

union clause ast = BC : (bits(5), bits(5), bits(14), bits(1), bits(1))

mapping clause encdec =
  BC(bo, bi, bd, aa, lk) <->
    0b010000 @ bo : bits(5) @ bi : bits(5) @ bd : bits(14) @ aa : bits(1) @ lk : bits(1)

function clause execute(BC(bo, bi, bd, aa, lk)) = {
  if lk == 0b1 then { harness_wrote(hw_lr); LR = CIA + 4 };  /* LR is set whether or not taken */
  if branch_cond_taken(bo, bi) then {
    let offset : word = exts(bd @ 0b00);
    harness_wrote(hw_nia);
    NIA = if aa == 0b1 then offset else CIA + offset
  };
  COMPLETED
}

/* --- bclr[l] / bcctr[l] BO,BI (XL-form) --------------------------------- */

/* Both take their target from a register, with the low two bits dropped:
 * the manual writes it LR[0-29] || b'00' / CTR[0-29] || b'00' (ch. 10
 * bclrx and bcctrx pages).  The target is read *before* the condition is
 * evaluated and before LR is written, which matters twice:
 *   - bclrl uses the old LR as the target and the new one as the return
 *     address (the manual's pseudocode orders it the same way);
 *   - bcctr with BO[2]=0 branches to the nondecremented CTR (see below).
 * The reserved bits 16-20 are decoded as zero, so a nonzero field is
 * ILLEGAL rather than boundedly undefined; that deviation is common to
 * every reserved field in the model and is tracked as one decision. */

union clause ast = BCLR : (bits(5), bits(5), bits(1))

mapping clause encdec =
  BCLR(bo, bi, lk) <->
    0b010011 @ bo : bits(5) @ bi : bits(5) @ 0b00000 @ 0b0000010000 @ lk : bits(1)

function clause execute(BCLR(bo, bi, lk)) = {
  let target : word = LR & 0xFFFFFFFC;
  if lk == 0b1 then { harness_wrote(hw_lr); LR = CIA + 4 };  /* LR is set whether or not taken */
  if branch_cond_taken(bo, bi) then { harness_wrote(hw_nia); NIA = target };
  COMPLETED
}

union clause ast = BCCTR : (bits(5), bits(5), bits(1))

mapping clause encdec =
  BCCTR(bo, bi, lk) <->
    0b010011 @ bo : bits(5) @ bi : bits(5) @ 0b00000 @ 0b1000010000 @ lk : bits(1)

function clause execute(BCCTR(bo, bi, lk)) = {
  let target : word = CTR & 0xFFFFFFFC;
  if lk == 0b1 then { harness_wrote(hw_lr); LR = CIA + 4 };
  /* INVALID-FORM: BO[2]=0 asks for "decrement and test CTR", which is
   * invalid for bcctr because CTR is also the target.  The 601 defines it
   * (ch. 10 bcctrx page): CTR is decremented and the decremented value is
   * what the CTR test sees, but instruction fetching goes to the address
   * taken from the nondecremented CTR — which is what `target`, read
   * above, holds.  branch_cond_taken does the decrement for us. */
  if branch_cond_taken(bo, bi) then { harness_wrote(hw_nia); NIA = target };
  COMPLETED
}

/* --- CR logical (Table 3-32) -------------------------------------------- */

/* All eight share one XL-form layout, 19 | crbD | crbA | crbB | XO | 0, and
 * all eight write a single CR bit.  crbD/crbA/crbB are CR bit numbers in
 * the manual's big-endian numbering, which is exactly what CRbit() takes.
 * None of them touches any other CR bit or any other register. */

union clause ast = CRAND : (bits(5), bits(5), bits(5))

mapping clause encdec =
  CRAND(crbD, crbA, crbB) <->
    0b010011 @ crbD : bits(5) @ crbA : bits(5) @ crbB : bits(5) @ 0b0100000001 @ 0b0

function clause execute(CRAND(crbD, crbA, crbB)) = {
  CRbit(crbD) = CRbit(crbA) & CRbit(crbB);
  COMPLETED
}

union clause ast = CROR : (bits(5), bits(5), bits(5))

mapping clause encdec =
  CROR(crbD, crbA, crbB) <->
    0b010011 @ crbD : bits(5) @ crbA : bits(5) @ crbB : bits(5) @ 0b0111000001 @ 0b0

function clause execute(CROR(crbD, crbA, crbB)) = {
  CRbit(crbD) = CRbit(crbA) | CRbit(crbB);
  COMPLETED
}

union clause ast = CRXOR : (bits(5), bits(5), bits(5))

mapping clause encdec =
  CRXOR(crbD, crbA, crbB) <->
    0b010011 @ crbD : bits(5) @ crbA : bits(5) @ crbB : bits(5) @ 0b0011000001 @ 0b0

function clause execute(CRXOR(crbD, crbA, crbB)) = {
  CRbit(crbD) = xor_vec(CRbit(crbA), CRbit(crbB));
  COMPLETED
}

union clause ast = CRNAND : (bits(5), bits(5), bits(5))

mapping clause encdec =
  CRNAND(crbD, crbA, crbB) <->
    0b010011 @ crbD : bits(5) @ crbA : bits(5) @ crbB : bits(5) @ 0b0011100001 @ 0b0

function clause execute(CRNAND(crbD, crbA, crbB)) = {
  CRbit(crbD) = not_vec(CRbit(crbA) & CRbit(crbB));
  COMPLETED
}

union clause ast = CRNOR : (bits(5), bits(5), bits(5))

mapping clause encdec =
  CRNOR(crbD, crbA, crbB) <->
    0b010011 @ crbD : bits(5) @ crbA : bits(5) @ crbB : bits(5) @ 0b0000100001 @ 0b0

function clause execute(CRNOR(crbD, crbA, crbB)) = {
  CRbit(crbD) = not_vec(CRbit(crbA) | CRbit(crbB));
  COMPLETED
}

union clause ast = CREQV : (bits(5), bits(5), bits(5))

mapping clause encdec =
  CREQV(crbD, crbA, crbB) <->
    0b010011 @ crbD : bits(5) @ crbA : bits(5) @ crbB : bits(5) @ 0b0100100001 @ 0b0

function clause execute(CREQV(crbD, crbA, crbB)) = {
  CRbit(crbD) = not_vec(xor_vec(CRbit(crbA), CRbit(crbB)));
  COMPLETED
}

union clause ast = CRANDC : (bits(5), bits(5), bits(5))

mapping clause encdec =
  CRANDC(crbD, crbA, crbB) <->
    0b010011 @ crbD : bits(5) @ crbA : bits(5) @ crbB : bits(5) @ 0b0010000001 @ 0b0

function clause execute(CRANDC(crbD, crbA, crbB)) = {
  CRbit(crbD) = CRbit(crbA) & not_vec(CRbit(crbB));
  COMPLETED
}

union clause ast = CRORC : (bits(5), bits(5), bits(5))

mapping clause encdec =
  CRORC(crbD, crbA, crbB) <->
    0b010011 @ crbD : bits(5) @ crbA : bits(5) @ crbB : bits(5) @ 0b0110100001 @ 0b0

function clause execute(CRORC(crbD, crbA, crbB)) = {
  CRbit(crbD) = CRbit(crbA) | not_vec(CRbit(crbB));
  COMPLETED
}

/* mcrf crfD,crfS (XO=0) copies a whole 4-bit CR field and leaves every
 * other field alone.  Layout: 19 | crfD | 00 | crfS | 00 | 00000 | 0 | LK.
 * INVALID-FORM: the architecture calls LK=1 invalid here, but the 601
 * executes the instruction and leaves LR "in an undefined state" (ch. 10
 * mcrf page) — so LK is decoded and ignored, and UNDEF: LR keeps its
 * previous value rather than being given an invented one. */

union clause ast = MCRF : (bits(3), bits(3), bits(1))

mapping clause encdec =
  MCRF(crfD, crfS, lk) <->
    0b010011 @ crfD : bits(3) @ 0b00 @ crfS : bits(3) @ 0b00
    @ 0b00000 @ 0b0000000000 @ lk : bits(1)

function clause execute(MCRF(crfD, crfS, _lk)) = {
  CRfield(unsigned(crfD)) = CRfield(unsigned(crfS));
  COMPLETED
}

$endif
