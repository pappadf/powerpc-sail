/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_insts_loadstore.sail — integer load/store instructions
 * (MPC601UM §3.5, ch. 10).
 *
 * IMPLEMENTED:
 *   lbz lbzx lbzu lbzux lhz lhzx lhzu lhzux lha lhax lhau lhaux
 *   lwz lwzx lwzu lwzux                        (Table 3-16)
 *   stb stbx stbu stbux sth sthx sthu sthux
 *   stw stwx stwu stwux                        (Table 3-17)
 *   lhbrx lwbrx sthbrx stwbrx                  (Table 3-18, byte-reverse)
 *   lmw stmw                                   (Table 3-19, multiple)
 *   lswi lswx stswi stswx                      (Table 3-20, move string)
 *   (lscbx is 601-only -> cores/p601/p601_insts_power.sail.)
 *
 * Alignment checking is PER-CORE — the 601's rules (§5.4.6.1, §5.4.6.3) and
 * the later cores' (§4.5.6 in each manual) genuinely differ — and lives
 * behind the core_alignment_fault hook; align_check below is the common
 * check-and-raise plumbing, applied by mem_read/mem_write.  String and
 * multiple instructions check their whole transfer up front instead and then
 * use mem_*_raw.  The floating-point loads and stores that carry Align_fp
 * live in ppc_insts_fp.sail (Tables 3-22/3-23 — stfiwx is NOT implemented
 * on the 601).
 */

$ifndef _PPC_INSTS_LOADSTORE
$define _PPC_INSTS_LOADSTORE

/* --- Alignment checks --------------------------------------------------- */

/* Does an n-byte access starting at ea run past the next boundary?  The
 * check covers the whole operand — for a string or multiple, the whole
 * transfer (§5.4.6.1). */
val crosses_256m : (word, int) -> bool
function crosses_256m(ea, n) = unsigned(ea[27 .. 0]) + n > 268435456

val crosses_4k : (word, int) -> bool
function crosses_4k(ea, n) = unsigned(ea[11 .. 0]) + n > 4096

/* The check-and-raise every access path shares: consult the core's rules
 * and, on a fault, take the alignment exception with the DAR value the core
 * specifies (the 603e stores EA + 4 for a misaligned multiple or atomic
 * operand — see core_alignment_dar in ppc_core_iface.sail).  Returns true
 * when the exception was taken.
 *
 * WHAT faults is a per-core decision: see cores/p601/p601_core.sail for the
 * 601's §5.4.6.1 rules and cores/common/ppc32_core.sail for the later
 * cores' §4.5.6 rules. */
val align_check : (word, int, AlignRule) -> bool
function align_check(ea, n, rule) =
  if core_alignment_fault(ea, n, rule) then {
    let _ = alignment_exception(core_alignment_dar(ea, rule));
    true
  } else false

/* Up-front range check for a string or multiple.  The check is performed
 * before the instruction begins, so a fault leaves no partial transfer
 * (§5.4.6.1); the per-word/per-byte accesses that follow therefore go
 * through the unchecked mem_*_raw path. */
val string_align_ok : (word, int, AlignRule) -> bool
function string_align_ok(ea, n, rule) = not_bool(align_check(ea, n, rule))

/* Data address breakpoint (§2.3.3.13.4).  Checked per individual
 * access — which for a string or multiple means once per word, as Table 2-26
 * requires — and before translation, since the compare is on the effective
 * address and is independent of MSR[DT] (§6.1.9).  A match inhibits the
 * access entirely: no memory is read or written, and the update form's
 * writeback to rA is suppressed too, which falls out of the None()/false
 * result meaning "no data".
 * An access that is both misaligned and a DABR match takes the alignment
 * exception, because mem_read/mem_write check alignment first.  Chapter 5
 * never orders the two, but §2.4.3.2 puts alignment exceptions "ahead of
 * data access exceptions" and a DABR match is a data access exception
 * (DSISR bit 9) — said there of the little-endian conditions, but the
 * classification holds either way. */
val breakpoint_fault : forall 'n, 'n in {1, 2, 4, 8}. (word, int('n), bool) -> bool
function breakpoint_fault(ea, width, is_store) =
  if core_data_breakpoint(ea, width, is_store) then {
    let _ = data_access_fault(Fault_DataBreakpoint, ea, is_store);
    true
  } else false

/* Translate + read for a data load, with no alignment check and no
 * breakpoint compare.  Returns None() if an exception was taken.  The WIM
 * mode the translation yields is not used here: the only instruction whose
 * behaviour depends on it is dcbz, which translates for itself
 * (ppc_insts_cache.sail).
 * `le_munge` applies little-endian addressing to the PHYSICAL address, after
 * everything that has to report the architectural one has done so.
 *
 * Called directly only by the one instruction Table 2-26 exempts from the
 * DABR — "this instruction is not supported by the DABR feature.  No DAE
 * occurs, even if the EA matches".  (Cache control instructions are exempt
 * too, but they translate for themselves.)  Everything else goes through
 * mem_read_raw or mem_read below. */
val mem_read_nodabr : forall 'n, 'n in {1, 2, 4, 8}. (word, int('n)) -> option(bits(8 * 'n))
function mem_read_nodabr(ea, width) =
  match translate_addr(ea, Mem_load) {
    TR_Address(pa, _) => Some(phys_read(le_munge(pa, width), width)),
    TR_Fault(cause) => {
      let _ = data_access_fault(cause, ea, false);
      None()
    }
  }

val mem_read_raw : forall 'n, 'n in {1, 2, 4, 8}. (word, int('n)) -> option(bits(8 * 'n))
function mem_read_raw(ea, width) =
  if breakpoint_fault(ea, width, false) then None()
  else mem_read_nodabr(ea, width)

val mem_write_raw : forall 'n, 'n in {1, 2, 4, 8}. (word, int('n), bits(8 * 'n)) -> bool
function mem_write_raw(ea, width, data) =
  if breakpoint_fault(ea, width, true) then false
  else match translate_addr(ea, Mem_store) {
    TR_Address(pa, _) => { phys_write(le_munge(pa, width), width, data); true },
    TR_Fault(cause) => {
      let _ = data_access_fault(cause, ea, true);
      false
    }
  }

/* The checked accessors every ordinary (non-string, non-multiple) load and
 * store goes through. */
val mem_read : forall 'n, 'n in {1, 2, 4, 8}. (word, int('n)) -> option(bits(8 * 'n))
function mem_read(ea, width) =
  if align_check(ea, width, Align_operand) then None()
  else mem_read_raw(ea, width)

val mem_write : forall 'n, 'n in {1, 2, 4, 8}. (word, int('n), bits(8 * 'n)) -> bool
function mem_write(ea, width, data) =
  if align_check(ea, width, Align_operand) then false
  else mem_write_raw(ea, width, data)

/* The floating-point accessors.  Identical to mem_read and mem_write but for
 * the alignment rule, which has more ways to fault — word-alignment on the
 * later cores, the I/O-segment rule on the 601 (§5.4.6.1.2). */
val mem_read_fp : forall 'n, 'n in {4, 8}. (word, int('n)) -> option(bits(8 * 'n))
function mem_read_fp(ea, width) =
  if align_check(ea, width, Align_fp) then None()
  else mem_read_raw(ea, width)

val mem_write_fp : forall 'n, 'n in {4, 8}. (word, int('n), bits(8 * 'n)) -> bool
function mem_write_fp(ea, width, data) =
  if align_check(ea, width, Align_fp) then false
  else mem_write_raw(ea, width, data)

/* --- Addressing modes --------------------------------------------------- */

/* Four ways to form an effective address (§3.5.1):
 *   D-form         (rA|0) + EXTS(d)
 *   X-form         (rA|0) + (rB)
 *   D-form update  (rA)   + EXTS(d)
 *   X-form update  (rA)   + (rB)
 *
 * The update forms read (rA), not (rA|0): rA = 0 is an invalid form for
 * them, and the ch. 10 pseudocode is written in terms of (rA) — which is
 * what makes the 601's documented rA = 0 execution ("the 601 supports
 * execution with rA=0 as shown above", stwu page) well defined: the access
 * goes to (r0) + d.  What that execution does NOT do is write r0 back; see
 * exec_load and exec_store below. */

val ea_d : (ridx, bits(16)) -> word
function ea_d(rA, d) = gpr_or_zero(rA) + exts(d)

val ea_x : (ridx, ridx) -> word
function ea_x(rA, rB) = gpr_or_zero(rA) + GPR(rB)

val ea_du : (ridx, bits(16)) -> word
function ea_du(rA, d) = GPR(rA) + exts(d)

val ea_xu : (ridx, ridx) -> word
function ea_xu(rA, rB) = GPR(rA) + GPR(rB)

/* Load `width` bytes into rD, zero- or sign-extended, then (for the update
 * forms) write the effective address back to rA.
 *
 * INVALID-FORM (ch. 10, lbzu/lwzux pages): the architecture calls a load
 * with update invalid when rA = 0 or rA = rD, and the 601 defines what it
 * does — the data is loaded and the register update is suppressed.  A fault
 * suppresses the update too, since the instruction does not complete. */
val exec_load : forall 'n, 'n in {1, 2, 4}.
  (ridx, ridx, word, int('n), bool, bool) -> Completion
function exec_load(rD, rA, ea, width, sign, update) =
  match mem_read(ea, width) {
    Some(v) => {
      GPR(rD) = if sign then exts(v) else extz(v);
      if update & (rA != 0b00000) & (rA != rD) then GPR(rA) = ea;
      COMPLETED
    },
    None() => EXCEPTION_TAKEN
  }

/* Store the low `width` bytes of rS, then (for the update forms) write the
 * effective address back to rA.
 *
 * INVALID-FORM (§3.5.3): the architecture calls a store with update invalid
 * when rA = 0, and the 601 defines what it does — "The PowerPC architecture
 * defines store with update instructions with rA = 0 as an invalid form.  In
 * the POWER architecture, this form is not considered invalid and in this
 * case rA is not updated.  To maintain compatibility with POWER in this
 * case, the 601 does not update register r0."  §3.5.2 says the identical
 * thing about the loads, which is why exec_load above suppresses too.
 *
 * TWO PASSAGES, ONE READING: the ch. 10 stbu/stwu/sthu pages say only "while
 * the PowerPC architecture defines the instruction form as invalid if rA=0,
 * the 601 supports execution with rA=0 as shown above", whose pseudocode
 * lists `rA <- EA` unconditionally.  That is the coarser statement — it is
 * making the point that the instruction EXECUTES rather than trapping — and
 * §3.5.3 is the one that spells out what happens to r0.  §3.5.8 settles it
 * for the pair by saying both at once about the floating-point forms: "the
 * 601 accesses memory for these cases but inhibits the update of the integer
 * register r0".  So: the memory access happens, the writeback to r0 does
 * not.  (This model previously followed the ch. 10 reading and updated r0.)
 *
 * Unlike the loads there is NO rA = rS suppression: §3.5.3's other rule is
 * "if rS = rA, the contents of register rS are copied to the target memory
 * element, then the generated EA is placed into rA" — the store happens
 * first and the writeback still lands.  rA = rD is a load-only conflict,
 * because only a load has two things to put in one register. */
val exec_store : forall 'n, 'n in {1, 2, 4}.
  (ridx, ridx, word, int('n), bool) -> Completion
function exec_store(rS, rA, ea, width, update) =
  if mem_write(ea, width, slice(GPR(rS), 0, 8 * width)) then {
    if update & (rA != 0b00000) then GPR(rA) = ea;
    COMPLETED
  } else EXCEPTION_TAKEN

/* --- Byte loads --------------------------------------------------------- */

union clause ast = LBZ : (ridx, ridx, bits(16))

mapping clause encdec =
  LBZ(rD, rA, d) <-> 0b100010 @ rD : ridx @ rA : ridx @ d : bits(16)

function clause execute(LBZ(rD, rA, d)) =
  exec_load(rD, rA, ea_d(rA, d), 1, false, false)

union clause ast = LBZU : (ridx, ridx, bits(16))

mapping clause encdec =
  LBZU(rD, rA, d) <-> 0b100011 @ rD : ridx @ rA : ridx @ d : bits(16)

function clause execute(LBZU(rD, rA, d)) =
  exec_load(rD, rA, ea_du(rA, d), 1, false, true)

union clause ast = LBZX : (ridx, ridx, ridx)

mapping clause encdec =
  LBZX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0001010111 @ 0b0

function clause execute(LBZX(rD, rA, rB)) =
  exec_load(rD, rA, ea_x(rA, rB), 1, false, false)

union clause ast = LBZUX : (ridx, ridx, ridx)

mapping clause encdec =
  LBZUX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0001110111 @ 0b0

function clause execute(LBZUX(rD, rA, rB)) =
  exec_load(rD, rA, ea_xu(rA, rB), 1, false, true)

/* --- Halfword loads, zero-extending ------------------------------------- */

union clause ast = LHZ : (ridx, ridx, bits(16))

mapping clause encdec =
  LHZ(rD, rA, d) <-> 0b101000 @ rD : ridx @ rA : ridx @ d : bits(16)

function clause execute(LHZ(rD, rA, d)) =
  exec_load(rD, rA, ea_d(rA, d), 2, false, false)

union clause ast = LHZU : (ridx, ridx, bits(16))

mapping clause encdec =
  LHZU(rD, rA, d) <-> 0b101001 @ rD : ridx @ rA : ridx @ d : bits(16)

function clause execute(LHZU(rD, rA, d)) =
  exec_load(rD, rA, ea_du(rA, d), 2, false, true)

union clause ast = LHZX : (ridx, ridx, ridx)

mapping clause encdec =
  LHZX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0100010111 @ 0b0

function clause execute(LHZX(rD, rA, rB)) =
  exec_load(rD, rA, ea_x(rA, rB), 2, false, false)

union clause ast = LHZUX : (ridx, ridx, ridx)

mapping clause encdec =
  LHZUX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0100110111 @ 0b0

function clause execute(LHZUX(rD, rA, rB)) =
  exec_load(rD, rA, ea_xu(rA, rB), 2, false, true)

/* --- Halfword loads, sign-extending ------------------------------------- */

union clause ast = LHA : (ridx, ridx, bits(16))

mapping clause encdec =
  LHA(rD, rA, d) <-> 0b101010 @ rD : ridx @ rA : ridx @ d : bits(16)

function clause execute(LHA(rD, rA, d)) =
  exec_load(rD, rA, ea_d(rA, d), 2, true, false)

union clause ast = LHAU : (ridx, ridx, bits(16))

mapping clause encdec =
  LHAU(rD, rA, d) <-> 0b101011 @ rD : ridx @ rA : ridx @ d : bits(16)

function clause execute(LHAU(rD, rA, d)) =
  exec_load(rD, rA, ea_du(rA, d), 2, true, true)

union clause ast = LHAX : (ridx, ridx, ridx)

mapping clause encdec =
  LHAX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0101010111 @ 0b0

function clause execute(LHAX(rD, rA, rB)) =
  exec_load(rD, rA, ea_x(rA, rB), 2, true, false)

union clause ast = LHAUX : (ridx, ridx, ridx)

mapping clause encdec =
  LHAUX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0101110111 @ 0b0

function clause execute(LHAUX(rD, rA, rB)) =
  exec_load(rD, rA, ea_xu(rA, rB), 2, true, true)

/* --- Word loads --------------------------------------------------------- */

union clause ast = LWZ : (ridx, ridx, bits(16))

mapping clause encdec =
  LWZ(rD, rA, d) <-> 0b100000 @ rD : ridx @ rA : ridx @ d : bits(16)

function clause execute(LWZ(rD, rA, d)) =
  exec_load(rD, rA, ea_d(rA, d), 4, false, false)

union clause ast = LWZU : (ridx, ridx, bits(16))

mapping clause encdec =
  LWZU(rD, rA, d) <-> 0b100001 @ rD : ridx @ rA : ridx @ d : bits(16)

function clause execute(LWZU(rD, rA, d)) =
  exec_load(rD, rA, ea_du(rA, d), 4, false, true)

union clause ast = LWZX : (ridx, ridx, ridx)

mapping clause encdec =
  LWZX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0000010111 @ 0b0

function clause execute(LWZX(rD, rA, rB)) =
  exec_load(rD, rA, ea_x(rA, rB), 4, false, false)

union clause ast = LWZUX : (ridx, ridx, ridx)

mapping clause encdec =
  LWZUX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0000110111 @ 0b0

function clause execute(LWZUX(rD, rA, rB)) =
  exec_load(rD, rA, ea_xu(rA, rB), 4, false, true)

/* --- Byte stores -------------------------------------------------------- */

union clause ast = STB : (ridx, ridx, bits(16))

mapping clause encdec =
  STB(rS, rA, d) <-> 0b100110 @ rS : ridx @ rA : ridx @ d : bits(16)

function clause execute(STB(rS, rA, d)) =
  exec_store(rS, rA, ea_d(rA, d), 1, false)

union clause ast = STBU : (ridx, ridx, bits(16))

mapping clause encdec =
  STBU(rS, rA, d) <-> 0b100111 @ rS : ridx @ rA : ridx @ d : bits(16)

function clause execute(STBU(rS, rA, d)) =
  exec_store(rS, rA, ea_du(rA, d), 1, true)

union clause ast = STBX : (ridx, ridx, ridx)

mapping clause encdec =
  STBX(rS, rA, rB) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0011010111 @ 0b0

function clause execute(STBX(rS, rA, rB)) =
  exec_store(rS, rA, ea_x(rA, rB), 1, false)

union clause ast = STBUX : (ridx, ridx, ridx)

mapping clause encdec =
  STBUX(rS, rA, rB) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0011110111 @ 0b0

function clause execute(STBUX(rS, rA, rB)) =
  exec_store(rS, rA, ea_xu(rA, rB), 1, true)

/* --- Halfword stores ---------------------------------------------------- */

union clause ast = STH : (ridx, ridx, bits(16))

mapping clause encdec =
  STH(rS, rA, d) <-> 0b101100 @ rS : ridx @ rA : ridx @ d : bits(16)

function clause execute(STH(rS, rA, d)) =
  exec_store(rS, rA, ea_d(rA, d), 2, false)

union clause ast = STHU : (ridx, ridx, bits(16))

mapping clause encdec =
  STHU(rS, rA, d) <-> 0b101101 @ rS : ridx @ rA : ridx @ d : bits(16)

function clause execute(STHU(rS, rA, d)) =
  exec_store(rS, rA, ea_du(rA, d), 2, true)

union clause ast = STHX : (ridx, ridx, ridx)

mapping clause encdec =
  STHX(rS, rA, rB) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0110010111 @ 0b0

function clause execute(STHX(rS, rA, rB)) =
  exec_store(rS, rA, ea_x(rA, rB), 2, false)

union clause ast = STHUX : (ridx, ridx, ridx)

mapping clause encdec =
  STHUX(rS, rA, rB) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0110110111 @ 0b0

function clause execute(STHUX(rS, rA, rB)) =
  exec_store(rS, rA, ea_xu(rA, rB), 2, true)

/* --- Word stores -------------------------------------------------------- */

union clause ast = STW : (ridx, ridx, bits(16))

mapping clause encdec =
  STW(rS, rA, d) <-> 0b100100 @ rS : ridx @ rA : ridx @ d : bits(16)

function clause execute(STW(rS, rA, d)) =
  exec_store(rS, rA, ea_d(rA, d), 4, false)

union clause ast = STWU : (ridx, ridx, bits(16))

mapping clause encdec =
  STWU(rS, rA, d) <-> 0b100101 @ rS : ridx @ rA : ridx @ d : bits(16)

function clause execute(STWU(rS, rA, d)) =
  exec_store(rS, rA, ea_du(rA, d), 4, true)

union clause ast = STWX : (ridx, ridx, ridx)

mapping clause encdec =
  STWX(rS, rA, rB) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0010010111 @ 0b0

function clause execute(STWX(rS, rA, rB)) =
  exec_store(rS, rA, ea_x(rA, rB), 4, false)

union clause ast = STWUX : (ridx, ridx, ridx)

mapping clause encdec =
  STWUX(rS, rA, rB) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0010110111 @ 0b0

function clause execute(STWUX(rS, rA, rB)) =
  exec_store(rS, rA, ea_xu(rA, rB), 4, true)

/* --- Byte-reverse ------------------------------------------------------- */

/* These move the operand with its bytes in the opposite order, which is how
 * a big-endian processor reads and writes little-endian data (§3.5.4).  All
 * four are X-form only: there is no D-form and no update variant. */

union clause ast = LHBRX : (ridx, ridx, ridx)

mapping clause encdec =
  LHBRX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b1100010110 @ 0b0

function clause execute(LHBRX(rD, rA, rB)) =
  match mem_read(ea_x(rA, rB), 2) {
    Some(v) => { GPR(rD) = extz(reverse_endianness(v)); COMPLETED },
    None()  => EXCEPTION_TAKEN
  }

union clause ast = LWBRX : (ridx, ridx, ridx)

mapping clause encdec =
  LWBRX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b1000010110 @ 0b0

function clause execute(LWBRX(rD, rA, rB)) =
  match mem_read(ea_x(rA, rB), 4) {
    Some(v) => { GPR(rD) = reverse_endianness(v); COMPLETED },
    None()  => EXCEPTION_TAKEN
  }

union clause ast = STHBRX : (ridx, ridx, ridx)

mapping clause encdec =
  STHBRX(rS, rA, rB) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1110010110 @ 0b0

function clause execute(STHBRX(rS, rA, rB)) =
  if mem_write(ea_x(rA, rB), 2, reverse_endianness(GPR(rS)[15 .. 0]))
  then COMPLETED else EXCEPTION_TAKEN

union clause ast = STWBRX : (ridx, ridx, ridx)

mapping clause encdec =
  STWBRX(rS, rA, rB) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1010010110 @ 0b0

function clause execute(STWBRX(rS, rA, rB)) =
  if mem_write(ea_x(rA, rB), 4, reverse_endianness(GPR(rS)))
  then COMPLETED else EXCEPTION_TAKEN

/* --- Load/store multiple ------------------------------------------------ */

/* lmw/stmw transfer consecutive words between memory at EA and the GPRs
 * from rD/rS up to r31 (§3.5.5).  A fault part-way through leaves the
 * transfers already made in place, which is why the loops below stop rather
 * than unwinding.
 *
 * The loop is written over the whole register file with a `r >= first`
 * guard rather than as a while loop, so the register index stays a
 * statically bounded 0..31 and can index GPRs directly. */

union clause ast = LMW : (ridx, ridx, bits(16))

mapping clause encdec =
  LMW(rD, rA, d) <-> 0b101110 @ rD : ridx @ rA : ridx @ d : bits(16)

function clause execute(LMW(rD, rA, d)) = {
  let base = ea_d(rA, d);
  let first = unsigned(rD);
  var ok : bool = string_align_ok(base, 4 * (32 - first), Align_multiple);
  foreach (r from 0 to 31) {
    if ok & (r >= first) then {
      match mem_read_raw(base + to_word(4 * (r - first)), 4) {
        Some(v) => {
          /* INVALID-FORM (ch. 10 lmw page): a base register inside the
           * loaded range is skipped, so it survives the whole transfer —
           * but rA = 0 is not used for addressing, so r0 is loaded. */
          if (rA == 0b00000) | (unsigned(rA) != r) then {
            harness_wrote(hw_gpr0 + get_slice_int(8, r, 0));
            GPRs[r] = v
          }
        },
        None() => { ok = false }
      }
    }
  };
  if ok then COMPLETED else EXCEPTION_TAKEN
}

union clause ast = STMW : (ridx, ridx, bits(16))

mapping clause encdec =
  STMW(rS, rA, d) <-> 0b101111 @ rS : ridx @ rA : ridx @ d : bits(16)

function clause execute(STMW(rS, rA, d)) = {
  let base = ea_d(rA, d);
  let first = unsigned(rS);
  var ok : bool = string_align_ok(base, 4 * (32 - first), Align_multiple);
  foreach (r from 0 to 31) {
    if ok & (r >= first) then {
      if not_bool(mem_write_raw(base + to_word(4 * (r - first)), 4, GPRs[r]))
      then ok = false
    }
  };
  if ok then COMPLETED else EXCEPTION_TAKEN
}

/* --- Move string -------------------------------------------------------- */

/* The string instructions move n bytes between memory and a run of GPRs
 * without any alignment requirement (§3.5.6).  Bytes fill each register
 * left to right (most significant byte first), the register sequence wraps
 * around through r0, and a partially filled last register has its remaining
 * low-order bytes cleared.
 *
 * n comes from the NB field (0 meaning 32) for the immediate forms and from
 * XER[25:31] for the indexed ones, so it ranges over 0..127 and can touch
 * every register — hence the loops below run over all 32.
 *
 * A zero-length lswx/stswx is an invalid form in the PowerPC architecture;
 * the 601 keeps POWER compatibility by executing it as a no-op that makes
 * no memory reference at all (§3.5.6, §5.4.3).  That falls out of n = 0. */

/* One-hot mask for a register number, used to build the inhibit set. */
val reg_mask_bit : ridx -> word
function reg_mask_bit(r) = sail_shiftleft(0x00000001, unsigned(r))

/* INVALID-FORM: the architecture calls a string load whose base register
 * lies in the loaded range invalid.  The 601 executes it POWER-style and
 * simply inhibits loading those registers, so the base survives the whole
 * transfer (§3.5.6).  rA = 0 is not used for addressing, so r0 is loaded. */
val string_load_inhibit : (ridx, word) -> word
function string_load_inhibit(rA, extra) =
  (if rA == 0b00000 then zeros(32) else reg_mask_bit(rA)) | extra

val exec_load_string : (ridx, word, int, word) -> Completion
function exec_load_string(rD, base, n, inhibit) = {
  /* A zero-length transfer makes no memory reference at all, so it cannot
   * fault (§5.4.3) — the check is skipped rather than run on n = 0. */
  var ok : bool = (n == 0) | string_align_ok(base, n, Align_string);
  foreach (m from 0 to 31) {
    let r = unsigned(add_bits_int(rD, m));   /* wraps mod 32 in 5 bits */
    var acc : word = zeros(32);
    var used : bool = false;
    foreach (j from 0 to 3) {
      let k = 4 * m + j;
      if ok & (k < n) then {
        match mem_read_raw(base + to_word(k), 1) {
          Some(b) => {
            acc = acc | sail_shiftleft(extz(b), 24 - 8 * j);
            used = true
          },
          None() => { ok = false }
        }
      }
    };
    if used & (inhibit[r] == bitzero) then {
      harness_wrote(hw_gpr0 + get_slice_int(8, r, 0));
      GPRs[r] = acc
    }
  };
  if ok then COMPLETED else EXCEPTION_TAKEN
}

val exec_store_string : (ridx, word, int) -> Completion
function exec_store_string(rS, base, n) = {
  var ok : bool = (n == 0) | string_align_ok(base, n, Align_string);
  foreach (m from 0 to 31) {
    let r = unsigned(add_bits_int(rS, m));
    foreach (j from 0 to 3) {
      let k = 4 * m + j;
      if ok & (k < n) then {
        let b = slice(sail_shiftright(GPRs[r], 24 - 8 * j), 0, 8);
        if not_bool(mem_write_raw(base + to_word(k), 1, b)) then { ok = false }
      }
    }
  };
  if ok then COMPLETED else EXCEPTION_TAKEN
}

/* Byte count of the immediate forms: NB, with 0 meaning 32. */
val string_nb : bits(5) -> int
function string_nb(nb) = if nb == 0b00000 then 32 else unsigned(nb)

union clause ast = LSWI : (ridx, ridx, bits(5))

mapping clause encdec =
  LSWI(rD, rA, nb) <->
    0b011111 @ rD : ridx @ rA : ridx @ nb : bits(5) @ 0b1001010101 @ 0b0

function clause execute(LSWI(rD, rA, nb)) =
  exec_load_string(rD, gpr_or_zero(rA), string_nb(nb),
                   string_load_inhibit(rA, zeros(32)))

union clause ast = LSWX : (ridx, ridx, ridx)

mapping clause encdec =
  LSWX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b1000010101 @ 0b0

function clause execute(LSWX(rD, rA, rB)) =
  exec_load_string(rD, ea_x(rA, rB), unsigned(XER[BC]),
                   string_load_inhibit(rA, reg_mask_bit(rB)))

union clause ast = STSWI : (ridx, ridx, bits(5))

mapping clause encdec =
  STSWI(rS, rA, nb) <->
    0b011111 @ rS : ridx @ rA : ridx @ nb : bits(5) @ 0b1011010101 @ 0b0

function clause execute(STSWI(rS, rA, nb)) =
  exec_store_string(rS, gpr_or_zero(rA), string_nb(nb))

union clause ast = STSWX : (ridx, ridx, ridx)

mapping clause encdec =
  STSWX(rS, rA, rB) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b1010010101 @ 0b0

function clause execute(STSWX(rS, rA, rB)) =
  exec_store_string(rS, ea_x(rA, rB), unsigned(XER[BC]))

$endif
