/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_insts_system.sail — system linkage, processor control and segment
 * register instructions (MPC601UM §3.6.7, §3.7, §3.8.3).
 *
 * IMPLEMENTED (worked examples): mfspr, mtspr (with privilege &
 * unimplemented-SPR semantics), sc, mfcr/mtcrf/mcrxr, mfmsr/mtmsr, rfi,
 * mtsr/mtsrin/mfsr/mfsrin, tlbie, eciwx/ecowx.
 */

$ifndef _PPC_INSTS_SYSTEM
$define _PPC_INSTS_SYSTEM

/* The 10-bit SPR field as it appears in the instruction has its two 5-bit
 * halves swapped: instruction field = spr[5:9] first?  NO — the field
 * encodes the LOW-order 5 bits of the SPR number in instruction bits 11-15
 * and the HIGH-order 5 bits in bits 16-20 (MPC601UM §3.7.2, Table 3-39
 * caveat noted in Table 2-21).  encdec captures the raw field msb-first as
 * it sits in the word (sail bits 20..11); this converts to the
 * architectural number. */
val sprno_of_field : bits(10) -> sprno
function sprno_of_field(raw) = raw[4 .. 0] @ raw[9 .. 5]

/* --- mfspr rD,SPR (XFX-form, XO=339) ------------------------------------ */

union clause ast = MFSPR : (ridx, bits(10))

mapping clause encdec =
  MFSPR(rD, sprf) <-> 0b011111 @ rD : ridx @ sprf : bits(10) @ 0b0101010011 @ 0b0

function clause execute(MFSPR(rD, sprf)) = {
  let n = sprno_of_field(sprf);
  /* Privilege check first (§2.6: privilege violation takes priority over
   * the unimplemented-SPR no-op). */
  if spr_is_privileged(n) & (MSR[PR] == 0b1) then
    program_exception(Prog_Privileged)
  else
    match read_spr(n) {
      Some(v) => { GPR(rD) = v; COMPLETED },
      None()  => {
        /* Unimplemented SPR: no-op on the 601 (§2.2.5, §2.6).
         * TODO when 603/604 land: illegal-instruction program exception
         * instead — route through a core hook. */
        COMPLETED
      }
    }
}

/* --- mtspr SPR,rS (XFX-form, XO=467) ------------------------------------ */

union clause ast = MTSPR : (ridx, bits(10))

mapping clause encdec =
  MTSPR(rS, sprf) <-> 0b011111 @ rS : ridx @ sprf : bits(10) @ 0b0111010011 @ 0b0

function clause execute(MTSPR(rS, sprf)) = {
  let n = sprno_of_field(sprf);
  if spr_is_privileged(n) & (MSR[PR] == 0b1) then
    program_exception(Prog_Privileged)
  else {
    let _ = write_spr(n, GPR(rS));  /* false = unimplemented -> no-op */
    COMPLETED
  }
}

/* Every supervisor-level instruction below shares this guard: executing one
 * with MSR[PR]=1 is a privileged-instruction program exception (§3.7.2). */
val in_user_mode : unit -> bool
function in_user_mode() = MSR[PR] == 0b1

/* --- Condition register / XER moves (Table 3-38) ------------------------ */

/* mfcr rD (X-form, XO=19): the whole CR, no side effects. */
union clause ast = MFCR : ridx

mapping clause encdec =
  MFCR(rD) <-> 0b011111 @ rD : ridx @ 0b00000 @ 0b00000 @ 0b0000010011 @ 0b0

function clause execute(MFCR(rD)) = {
  GPR(rD) = CR;
  COMPLETED
}

/* mtcrf CRM,rS (XFX-form, XO=144): CRM is a field mask, one bit per CR
 * field, msb-first — CRM bit 0 (manual) selects CR field 0.  Fields whose
 * mask bit is zero keep their value, so this is written as a copy of the
 * selected fields rather than the manual's mask-and-merge; the result is
 * the same and it needs no 32-bit mask to be built.  CRM sits in
 * instruction bits 12-19, between two reserved bits. */
union clause ast = MTCRF : (ridx, bits(8))

mapping clause encdec =
  MTCRF(rS, crm) <->
    0b011111 @ rS : ridx @ 0b0 @ crm : bits(8) @ 0b0 @ 0b0010010000 @ 0b0

function clause execute(MTCRF(rS, crm)) = {
  let s = GPR(rS);
  foreach (n from 0 to 7) {
    /* CR field n is selected by manual CRM bit n = sail crm[7 - n]. */
    if crm[7 - n] == bitone then CRfield(n, slice(s, 28 - 4 * n, 4))
  };
  COMPLETED
}

/* mcrxr crfD (X-form, XO=512): copies XER[0:3] into a CR field and then
 * clears them.  XER manual bits 0-2 are SO/OV/CA and bit 3 is reserved, so
 * the CR field's SO position always receives zero. */
union clause ast = MCRXR : bits(3)

mapping clause encdec =
  MCRXR(crfd) <->
    0b011111 @ crfd : bits(3) @ 0b00 @ 0b00000 @ 0b00000 @ 0b1000000000 @ 0b0

function clause execute(MCRXR(crfd)) = {
  CRfield(unsigned(crfd), XER.bits[31 .. 28]);
  XER = Mk_Xer(XER.bits & 0x0FFFFFFF);
  COMPLETED
}

/* --- Machine state register (Table 3-38) -------------------------------- */

/* mfmsr rD (X-form, XO=83), supervisor.  Reserved MSR bits read as zero,
 * which write_msr already guarantees of the stored value. */
union clause ast = MFMSR : ridx

mapping clause encdec =
  MFMSR(rD) <-> 0b011111 @ rD : ridx @ 0b00000 @ 0b00000 @ 0b0001010011 @ 0b0

function clause execute(MFMSR(rD)) =
  if in_user_mode() then program_exception(Prog_Privileged)
  else {
    GPR(rD) = MSR.bits;
    COMPLETED
  }

/* mtmsr rS (X-form, XO=146), supervisor.  The whole register is written,
 * reserved bits excepted (§2.3.1: "attempting to change these bits does not
 * affect the operation").  The manual calls mtmsr execution synchronizing;
 * the model executes one instruction at a time, so that is automatic.
 * Tables 2-15/2-16 require a context-synchronizing event AFTER an mtmsr
 * that changes IT or DT.  That is a rule software must follow, not
 * behaviour the processor implements, and a model that completes one
 * instruction at a time has nothing to synchronize. */
union clause ast = MTMSR : ridx

mapping clause encdec =
  MTMSR(rS) <-> 0b011111 @ rS : ridx @ 0b00000 @ 0b00000 @ 0b0010010010 @ 0b0

function clause execute(MTMSR(rS)) =
  if in_user_mode() then program_exception(Prog_Privileged)
  else {
    write_msr(GPR(rS));
    COMPLETED
  }

/* --- rfi (XL-form, XO=50) ----------------------------------------------- */

/* Supervisor.  MSR[16:31] <- SRR1[16:31] and NIA <- SRR0[0:29] || 0b00
 * (ch. 10 rfi page).  MSR[0:15] is left alone, which on this core means
 * left at zero; write_msr drops the reserved bits SRR1 may be carrying. */
union clause ast = RFI : unit

mapping clause encdec =
  RFI() <-> 0b010011 @ 0b00000 @ 0b00000 @ 0b00000 @ 0b0000110010 @ 0b0

function clause execute(RFI()) =
  if in_user_mode() then program_exception(Prog_Privileged)
  else {
    write_msr(MSR.bits[31 .. 16] @ SRR1[15 .. 0]);
    NIA = SRR0 & 0xFFFFFFFC;
    COMPLETED
  }

/* --- Segment registers (Table 3-45) ------------------------------------- */

/* All four are supervisor-level and 32-bit-only (a 64-bit implementation has
 * no segment registers at all — §6.1.11 — and takes an illegal-instruction
 * program exception instead; the model targets 32-bit implementations only,
 * so there is nothing to do here).  The direct forms name the segment
 * register in instruction bits 12-15 with bit 11 reserved; the indirect
 * forms take it from rB[0:3], the top four bits of the register — the same
 * four bits of an effective address that select a segment.
 *
 * NOTE the 601 also invalidates the ITLB on mtsr/mtsrin (§6.2). No TLB is
 * modelled (see tlbie below), so there is nothing to invalidate. */

union clause ast = MTSR : (ridx, sridx)

mapping clause encdec =
  MTSR(rS, sr) <->
    0b011111 @ rS : ridx @ 0b0 @ sr : sridx @ 0b00000 @ 0b0011010010 @ 0b0

function clause execute(MTSR(rS, sr)) =
  if in_user_mode() then program_exception(Prog_Privileged)
  else {
    wSR(sr, GPR(rS));
    COMPLETED
  }

union clause ast = MFSR : (ridx, sridx)

mapping clause encdec =
  MFSR(rD, sr) <->
    0b011111 @ rD : ridx @ 0b0 @ sr : sridx @ 0b00000 @ 0b1001010011 @ 0b0

function clause execute(MFSR(rD, sr)) =
  if in_user_mode() then program_exception(Prog_Privileged)
  else {
    GPR(rD) = rSR(sr).bits;
    COMPLETED
  }

union clause ast = MTSRIN : (ridx, ridx)

mapping clause encdec =
  MTSRIN(rS, rB) <->
    0b011111 @ rS : ridx @ 0b00000 @ rB : ridx @ 0b0011110010 @ 0b0

function clause execute(MTSRIN(rS, rB)) =
  if in_user_mode() then program_exception(Prog_Privileged)
  else {
    wSR(GPR(rB)[31 .. 28], GPR(rS));
    COMPLETED
  }

union clause ast = MFSRIN : (ridx, ridx)

mapping clause encdec =
  MFSRIN(rD, rB) <->
    0b011111 @ rD : ridx @ 0b00000 @ rB : ridx @ 0b1010010011 @ 0b0

function clause execute(MFSRIN(rD, rB)) =
  if in_user_mode() then program_exception(Prog_Privileged)
  else {
    GPR(rD) = rSR(GPR(rB)[31 .. 28]).bits;
    COMPLETED
  }

/* --- tlbie rB (X-form, XO=306) ------------------------------------------ */

/* Supervisor-level, and architecturally a no-op for this model: no TLB is
 * modelled, and none is planned.  translate_addr walks the translation
 * afresh for every access, which is observationally equivalent to a TLB
 * that is always coherent with the page tables — the difference a real TLB
 * makes is precisely what tlbie exists to repair.  The one place the
 * equivalence is imperfect is reference/change-bit updates, which a real
 * TLB can defer (§6.8.4); that is a known deviation, not a reason to
 * model a TLB.  601: tlbia and tlbsync do not exist, so their opcodes are
 * correctly left to decode as illegal. */
union clause ast = TLBIE : ridx

mapping clause encdec =
  TLBIE(rB) <-> 0b011111 @ 0b00000 @ 0b00000 @ rB : ridx @ 0b0100110010 @ 0b0

function clause execute(TLBIE(_rB)) =
  if in_user_mode() then program_exception(Prog_Privileged)
  else COMPLETED

/* --- External control (Table 3-47) -------------------------------------- */

/* eciwx rD,rA,rB (X-form, XO=310) and ecowx rS,rA,rB (XO=438) move a word
 * between a register and a device named by EAR[RID], bypassing the cache.
 * Both are user-level — EAR[E] is what gates them — and both compute the
 * ordinary X-form EA (rA|0)+(rB).  Three outcomes (ch. 10 pages, §6.10):
 *
 *  - EAR[E]=0: data access exception with DSISR[11] set (Table 5-10);
 *  - the EA lies in an I/O controller interface segment (SR[T]=1): no-op;
 *  - otherwise the word goes to or comes from a device, and no device is
 *    modelled — a scaffold hole that throws rather than inventing data.
 *
 * An unaligned EA is boundedly undefined rather than an alignment
 * exception, so there is no alignment check.  601: both are accepted with
 * MSR[DT]=0 as well as 1, where the architecture requires 1 — nothing to
 * do about that here, since translation is not consulted on either of the
 * two paths the model can complete. */

val external_control_fault : word -> Completion
function external_control_fault(ea) = {
  DAR = ea;
  DSISR = 0x00100000;   /* manual bit 11: eciwx/ecowx with EAR[E]=0 */
  data_access_exception()
}

/* SR[T]=1 for the segment the EA falls in (EA[0:3] selects it). */
val ea_in_io_segment : word -> bool
function ea_in_io_segment(ea) = rSR(ea[31 .. 28])[T] == 0b1

union clause ast = ECIWX : (ridx, ridx, ridx)

mapping clause encdec =
  ECIWX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0100110110 @ 0b0

function clause execute(ECIWX(_rD, rA, rB)) = {
  let ea = ea_x(rA, rB);
  if EAR[E] == 0b0 then external_control_fault(ea)
  else if ea_in_io_segment(ea) then COMPLETED
  else throw(Model_unimplemented("eciwx: no external control device"))
}

union clause ast = ECOWX : (ridx, ridx, ridx)

mapping clause encdec =
  ECOWX(rS, rA, rB) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0110110110 @ 0b0

function clause execute(ECOWX(_rS, rA, rB)) = {
  let ea = ea_x(rA, rB);
  if EAR[E] == 0b0 then external_control_fault(ea)
  else if ea_in_io_segment(ea) then COMPLETED
  else throw(Model_unimplemented("ecowx: no external control device"))
}

/* --- sc (SC-form) ------------------------------------------------------- */

/* System call: SRR0 <- address of the NEXT instruction, SRR1[0:15] <- bits
 * 16-31 of the instruction itself.  Those bits are undefined in the
 * architecture; the 601 defines them, and the ch. 10 SC page's POWER
 * compatibility note gives two more 601 deviations in the same breath:
 *
 *  - bit 30, which the architecture requires to be 1 (a word with 0 there
 *    is reserved), is ignored during decode and execution;
 *  - INVALID-FORM: bit 31 (LK) set is invalid in the architecture, but the
 *    601 executes it and links, putting CIA+4 in LR — POWER's svca did
 *    that and the 601 keeps it.
 *
 * All three want the low half of the instruction word, so the ast carries
 * it whole: lo[0] is LK, lo[1] is the ignored bit 30, and lo entire is
 * what SRR1[0:15] receives. */
union clause ast = SC : bits(16)

mapping clause encdec =
  SC(lo) <-> 0b010001 @ 0b00000 @ 0b00000 @ lo : bits(16)

function clause execute(SC(lo)) = {
  /* Harness exit convention (NOT architectural — see ppc_debug.sail): sc
   * with the halt magic in GPR0 stops the emulator instead of vectoring,
   * reporting GPR3 as the exit status.  A test program that wants to
   * exercise the real system call exception simply uses any other GPR0. */
  if GPR(0b00000) == halt_magic then {
    request_halt(GPR(0b00011));
    COMPLETED
  } else {
    if lo[0] == bitone then LR = CIA + 4;   /* 601: sc with LK=1 links */
    take_exception(E_SystemCall, CIA + 4, lo);
    EXCEPTION_TAKEN   /* the sc itself completed, but control transferred */
  }
}

$endif
