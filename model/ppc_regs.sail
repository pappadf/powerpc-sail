/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_regs.sail — architected state common to all 32-bit PowerPC cores
 * (UISA + OEA registers).  Core-specific registers (MQ, RTC, HIDs, BATs on
 * the 601) live in the core directory.
 *
 * All bitfield comments give the manual's big-endian bit numbers;
 * sail dec index = 31 - manual index (see prelude.sail).
 */

$ifndef _PPC_REGS
$define _PPC_REGS

/* --- Program counter ---------------------------------------------------- */

register CIA : word  /* current instruction address */
register NIA : word  /* next instruction address    */

/* --- Instruction latch (model-internal, not architected) ---------------- */

/* The word being executed, latched by step() after fetch.  This is not
 * programmer-visible state, but the architecture defines the DSISR image an
 * alignment exception leaves behind directly in terms of the excepting
 * instruction's encoding (Table 5-13), and the decoded ast has already
 * thrown those bits away.  Keeping the raw word is far simpler than
 * threading a DSISR image through every load and store.
 * See dsisr_align_image in ppc_exceptions.sail. */
register cur_instr : bits(32)

/* --- General purpose and floating-point registers ----------------------- */

register GPRs : vector(32, word)
register FPRs : vector(32, bits(64))

val rGPR : ridx -> word
function rGPR(r) = GPRs[unsigned(r)]

val wGPR : (ridx, word) -> unit
function wGPR(r, v) = { harness_wrote(hw_gpr0 + (0b000 @ r)); GPRs[unsigned(r)] = v }

overload GPR = {rGPR, wGPR}

val rFPR : fridx -> bits(64)
function rFPR(r) = FPRs[unsigned(r)]

val wFPR : (fridx, bits(64)) -> unit
function wFPR(r, v) = { harness_wrote(hw_fpr0 + (0b000 @ r)); FPRs[unsigned(r)] = v }

overload FPR = {rFPR, wFPR}

/* --- Condition register (MPC601UM §2.2.4) ------------------------------- */

/* Eight 4-bit fields CR0..CR7; CR0 = manual bits 0-3 = sail bits 31..28.
 * Within a field: bit 0 = LT, 1 = GT, 2 = EQ, 3 = SO (for integer ops). */
register CR : word

/* Read CR field n (0..7) as a 4-bit value (manual bit order preserved:
 * result[3]=LT, result[2]=GT, result[1]=EQ, result[0]=SO). */
val rCRfield : forall 'n, 0 <= 'n < 8. int('n) -> bits(4)
function rCRfield(n) = slice(CR, 28 - 4 * n, 4)

val wCRfield : forall 'n, 0 <= 'n < 8. (int('n), bits(4)) -> unit
function wCRfield(n, v) = {
  harness_note_write(hw_cr, sail_shiftleft(0x0000000F, 28 - 4 * n));
  CR = update_subrange_bits(CR, 31 - 4 * n, 28 - 4 * n, v)
}

overload CRfield = {rCRfield, wCRfield}

/* Read/write a single CR bit by its big-endian (manual/instruction-field)
 * index 0..31, as used by the BI field of bc and by CR-logical instructions. */
val rCRbit : bits(5) -> bits(1)
function rCRbit(bi) = [CR[31 - unsigned(bi)]]

val wCRbit : (bits(5), bits(1)) -> unit
function wCRbit(bi, v) = {
  harness_note_write(hw_cr, sail_shiftleft(0x00000001, 31 - unsigned(bi)));
  CR[31 - unsigned(bi)] = v[0]
}

overload CRbit = {rCRbit, wCRbit}

/* --- Fixed-point exception register XER (SPR 1, §2.2.5.2, Table 2-8) ---- */

bitfield Xer : word = {
  SO : 31,        /* manual bit 0: summary overflow (sticky)                */
  OV : 30,        /* manual bit 1: overflow                                 */
  CA : 29,        /* manual bit 2: carry                                    */
  /* manual bits 16-23 (sail 15..8): byte to be compared by lscbx — this
   * field is 601-only but harmless to define here.  TODO: decide whether
   * to push it into the core layer when adding 603/604 (where these bits
   * are reserved). */
  CMPB : 15 .. 8,
  BC : 6 .. 0     /* manual bits 25-31: byte count for lswx/stswx/lscbx     */
}
register XER : Xer

/* Which bits of XER each named field occupies, for the harness write hook
 * (ppc_harness.sail).  Derived from the bitfield above rather than written
 * out, so that moving a field moves its mask with it. */
let hw_xer_so : word = [Mk_Xer(zeros(32)) with SO = 0b1].bits
let hw_xer_ov : word = [Mk_Xer(zeros(32)) with OV = 0b1].bits
let hw_xer_ca : word = [Mk_Xer(zeros(32)) with CA = 0b1].bits
let hw_xer_bc : word = [Mk_Xer(zeros(32)) with BC = 0b1111111].bits

/* Standard CR0 update for Rc=1 integer instructions: LT/GT/EQ from a signed
 * compare of the result with zero, SO copied from XER[SO]. */
val set_cr0 : word -> unit
function set_cr0(res) = {
  let lt = bool_to_bits(signed(res) < 0);
  let gt = bool_to_bits(signed(res) > 0);
  let eq = bool_to_bits(res == zeros(32));
  CRfield(0, lt @ gt @ eq @ XER[SO])
}

/* --- Link register / count register (SPRs 8, 9) ------------------------- */

register LR : word
register CTR : word

/* --- Machine state register (§2.3.1, Table 2-9) ------------------------- */

/* Bits shown are the 32-bit PowerPC OEA set as implemented by the 601.
 * NOTE 601 deviations (all reserved-on-601): no POW, no ILE, no BE (manual
 * bit 22), no RI (bit 30), no LE (bit 31, LE mode is HID0[LM] instead).
 * When adding 603/604, add POW/ILE/BE/RI/LE here and gate their behaviour
 * through the core interface. */
bitfield Msr : word = {
  EE  : 15,  /* manual bit 16: external/decrementer interrupt enable   */
  PR  : 14,  /* manual bit 17: privilege level (0=supervisor, 1=user)  */
  FP  : 13,  /* manual bit 18: floating-point available                */
  ME  : 12,  /* manual bit 19: machine check enable                    */
  FE0 : 11,  /* manual bit 20: FP exception mode 0                     */
  SE  : 10,  /* manual bit 21: single-step trace enable                */
  FE1 : 8,   /* manual bit 23: FP exception mode 1                     */
  EP  : 6,   /* manual bit 25: exception prefix (0 -> 0x000n_nnnn,
                                                 1 -> 0xFFFn_nnnn)     */
  IT  : 5,   /* manual bit 26: instruction address translation enable  */
  DT  : 4    /* manual bit 27: data address translation enable         */
}
register MSR : Msr

/* The bits the MSR actually implements, as a mask over the whole register.
 * Reserved bits cannot be changed and always read as zero (§2.3.1, note
 * under Table 2-9), so every instruction that writes a whole MSR value —
 * mtmsr and rfi — masks through this.  It must list exactly the fields of
 * the bitfield above; when a core with a different set arrives (603/604
 * add POW/ILE/BE/RI/LE) the implemented set becomes core-specific and this
 * belongs behind a core hook alongside those fields. */
let msr_implemented : word = 0x0000FD70

val write_msr : word -> unit
function write_msr(v) = { harness_wrote(hw_msr); MSR = Mk_Msr(v & msr_implemented) }

val privilege_level : unit -> PrivilegeLevel
function privilege_level() = if MSR[PR] == 0b1 then User else Supervisor

/* Are floating-point enabled exceptions enabled?  §5.4.7 states the
 * condition architecturally as (MSR[FE0] | MSR[FE1]) & FPSCR[FEX], so the
 * OR belongs in common code.  What is 601-specific is that the OR is ALL
 * there is: Table 2-10's two imprecise modes do not exist on this core
 * ("because FE0 and FE1 are logically ORed on the 601, neither of these
 * modes is available; if either bit is set, the processor operates in
 * precise mode"), so there is no mode to distinguish and no imprecise
 * reporting path to build.  A core that implements the imprecise modes will
 * need to read the two bits separately. */
val fp_exceptions_enabled : unit -> bool
function fp_exceptions_enabled() = (MSR[FE0] | MSR[FE1]) == 0b1

/* --- Floating-point status and control register (§2.2.3, Table 2-1) ----- */

/* The instructions that read and write these bits are in ppc_insts_fp.sail.
 * 601 notes: VXSOFT (manual bit 21) and VXSQRT (bit 22) are NOT implemented
 * on the 601; manual bit 29 (NI on later cores) is reserved. */
bitfield Fpscr : word = {
  FX      : 31,       /* manual bit 0: exception summary                  */
  FEX     : 30,       /* 1: enabled exception summary                     */
  VX      : 29,       /* 2: invalid operation exception summary           */
  OX      : 28,       /* 3: overflow                                      */
  UX      : 27,       /* 4: underflow                                     */
  ZX      : 26,       /* 5: zero divide                                   */
  XX      : 25,       /* 6: inexact                                       */
  VXSNAN  : 24,       /* 7 */
  VXISI   : 23,       /* 8 */
  VXIDI   : 22,       /* 9 */
  VXZDZ   : 21,       /* 10 */
  VXIMZ   : 20,       /* 11 */
  VXVC    : 19,       /* 12 */
  FR      : 18,       /* 13: fraction rounded                             */
  FI      : 17,       /* 14: fraction inexact                             */
  FPRF    : 16 .. 12, /* 15-19: result flags (C, FL, FG, FE, FU)          */
  FPCC    : 15 .. 12, /* 16-19: the condition-code half of FPRF, which the
                         compare instructions set on their own            */
  VXCVI   : 8,        /* 23 */
  VE      : 7,        /* 24: invalid op exception enable                  */
  OE      : 6,        /* 25 */
  UE      : 5,        /* 26 */
  ZE      : 4,        /* 27 */
  XE      : 3,        /* 28 */
  RN      : 1 .. 0    /* 30-31: rounding mode (00 nearest, 01 trunc,
                                 10 +inf, 11 -inf)                        */
}
register FPSCR : Fpscr

/* Masks for the harness write hook, as for XER above: the FPSCR is written a
 * field at a time by fpscr_raise and friends (ppc_insts_fp.sail), and a
 * consumer that names the fields separately needs to know which one moved. */
let hw_fpscr_fx   : word = [Mk_Fpscr(zeros(32)) with FX = 0b1].bits
let hw_fpscr_fex  : word = [Mk_Fpscr(zeros(32)) with FEX = 0b1].bits
let hw_fpscr_vx   : word = [Mk_Fpscr(zeros(32)) with VX = 0b1].bits
let hw_fpscr_fr   : word = [Mk_Fpscr(zeros(32)) with FR = 0b1].bits
let hw_fpscr_fi   : word = [Mk_Fpscr(zeros(32)) with FI = 0b1].bits
let hw_fpscr_fprf : word = [Mk_Fpscr(zeros(32)) with FPRF = 0b11111].bits
let hw_fpscr_fpcc : word = [Mk_Fpscr(zeros(32)) with FPCC = 0xF].bits

/* --- Exception handling registers (OEA, §2.3.3) ------------------------- */

register SRR0 : word    /* SPR 26: saved PC                    */
register SRR1 : word    /* SPR 27: saved status + MSR[16:31]   */
register DAR : word     /* SPR 19: faulting data address       */
register DSISR : word   /* SPR 18: data-fault status           */
register SPRG0 : word   /* SPRs 272-275: OS scratch            */
register SPRG1 : word
register SPRG2 : word
register SPRG3 : word

/* --- Decrementer (SPR 22; user-readable as SPR 6 on the 601) ------------ */

register DEC : word
register DEC_pending : bool  /* latched decrementer exception request */

/* Only the 25 most-significant bits of the DEC exist on the 601: manual bits
 * 0-24, so the low seven read as zero and a write ignores them (§2.3.3.5).
 * Like msr_implemented this is per-core in principle — the rate and the
 * implemented width are both implementation-defined — and moves behind a
 * core hook when a core with a different decrementer arrives. */
let dec_implemented : word = 0xFFFFFF80

/* The single place the DEC is written, by mtspr and by the timer alike.
 * "Whenever bit 0 of the decrementer changes from 0 to 1, an exception
 * request is signaled", explicitly including when software causes it
 * (§2.3.3.5, §5.4.9) — which is why the latch lives here rather than in the
 * tick.  Multiple requests before the exception is taken collapse into one,
 * which a boolean gives for free. */
val set_dec : word -> unit
function set_dec(v) = {
  let next = v & dec_implemented;
  if (DEC[31] == bitzero) & (next[31] == bitone) then DEC_pending = true;
  harness_wrote(hw_dec);
  DEC = next
}

/* --- External interrupt input (model-internal, not architected) --------- */

/* The 601 latches an external interrupt from the INT signal (§5.4.5).  This
 * model has no platform to assert it, so nothing calls
 * request_external_interrupt yet; it is the entry point whatever eventually
 * does will use.  Held until the exception is taken, mirroring the
 * level-sensitive input the manual describes. */
register ext_int_pending : bool

val request_external_interrupt : bool -> unit
function request_external_interrupt(asserted) = { ext_int_pending = asserted }

/* --- Storage description register SDR1 (SPR 25, §2.3.3.6) --------------- */

bitfield Sdr1 : word = {
  HTABORG  : 31 .. 16,  /* manual bits 0-15: phys base of page table   */
  HTABMASK : 8 .. 0     /* manual bits 23-31: mask for table size      */
}
register SDR1 : Sdr1

/* --- External access register EAR (SPR 282, §2.3.3.10) ------------------ */

/* E gates eciwx/ecowx; RID names the target device (Table 2-18).  The 601
 * puts RID in manual bits 28-31; everything between is reserved. */
bitfield Ear : word = {
  E   : 31,       /* manual bit 0: external control enable  */
  RID : 3 .. 0    /* manual bits 28-31: resource ID         */
}
register EAR : Ear

/* --- Segment registers (§2.3.2, §6.10) ---------------------------------- */

/* Sixteen 32-bit segment registers, selected by EA[0:3] (top 4 bits).
 * Two formats depending on the T bit: */
bitfield SegReg : word = {
  T    : 31,        /* manual bit 0: 0 = memory segment, 1 = I/O ctl segment */
  Ks   : 30,        /* manual bit 1: supervisor key                          */
  Ku   : 29,        /* manual bit 2: user key                                */
  VSID : 23 .. 0,   /* manual bits 8-31 (T=0): virtual segment ID            */
  /* T=1 (I/O controller interface segment, POWER holdover — implemented on
   * the 601; later cores treat T=1 as "direct-store", 604 drops it):       */
  BUID : 28 .. 20,  /* manual bits 3-11 (T=1): bus unit ID; 0x07F selects
                       memory-forced I/O (MPC601UM §6.10.1)                  */
  P1 : 3 .. 0       /* manual bits 28-31 (T=1): address bits 0-3 of the
                       packet 1 cycle, which for a memory-forced access are
                       the top four bits of the physical address (§6.10.4)   */
  /* Manual bits 12-27 (T=1) carry device-specific data (Table 6-20), which
     only a real device transaction would use — and those throw.            */
}
register SRs : vector(16, word)

val rSR : sridx -> SegReg
function rSR(n) = Mk_SegReg(SRs[unsigned(n)])

val wSR : (sridx, word) -> unit
function wSR(n, v) = { harness_wrote(hw_sr0 + (0b0000 @ n)); SRs[unsigned(n)] = v }

/* --- Common reset ------------------------------------------------------- */

/* Architected common reset state; core_reset() runs afterwards and may
 * override (e.g. 601 sets MSR[ME], MSR[EP]).  MPC601UM §2.7.1: hard reset
 * clears GPRs, CR, XER, LR, CTR, SRs, etc. */
val reset_common_regs : unit -> unit
function reset_common_regs() = {
  foreach (i from 0 to 31) {
    GPRs[i] = zeros(32);
    FPRs[i] = zeros(64)
  };
  foreach (i from 0 to 15) {
    SRs[i] = zeros(32)
  };
  CR = zeros(32);
  XER = Mk_Xer(zeros(32));
  LR = zeros(32);
  CTR = zeros(32);
  MSR = Mk_Msr(zeros(32));
  FPSCR = Mk_Fpscr(zeros(32));
  SRR0 = zeros(32);
  SRR1 = zeros(32);
  DAR = zeros(32);
  DSISR = zeros(32);
  SPRG0 = zeros(32);
  SPRG1 = zeros(32);
  SPRG2 = zeros(32);
  SPRG3 = zeros(32);
  DEC = zeros(32);
  DEC_pending = false;
  ext_int_pending = false;
  SDR1 = Mk_Sdr1(zeros(32));
  EAR = Mk_Ear(zeros(32));
  cur_instr = zeros(32)
}

$endif
